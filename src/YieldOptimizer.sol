// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDEXRouter} from "./interfaces/IDEXRouter.sol";
import {IYieldFarm} from "./interfaces/IYieldFarm.sol";
import {ISomniaReactivity} from "./interfaces/ISomniaReactivity.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title YieldOptimizer
/// @author Hash-Hokage
/// @notice A secure, gas-efficient yield optimizer that rebalances across ERC-4626 vaults
///         using Somnia's reactive callback system.
/// @dev This contract is designed to:
///      - Receive real-time APY updates via `ISomniaReactivity.onYieldUpdated`.
///      - Rebalance USDC across yield farms when a better rate is detected.
///      - Execute swaps through a Uniswap V2-style DEX router with strict slippage protection.
///      - Enforce a cumulative loss threshold ("RiskGuard") that pauses operations if breached.
///
///      **Architecture Notes:**
///      - Immutable addresses are set once at deployment and cannot be changed.
///      - RiskGuard state (`isPaused`, `maxLossThreshold`, `cumulativeLoss`) is
///        intentionally packed to minimise storage slot usage.
///      - Reactivity cache stores the latest reserve snapshot used for slippage calculations.
///
///      **Somnia Gas Model (Critical):**
///      Somnia's gas costs differ significantly from Ethereum:
///        - Cold `SLOAD` costs ~1,000,000 gas (~476× Ethereum).
///        - `LOG` opcodes cost ~13× Ethereum.
///      This handler performs multiple cold storage reads and cross-contract calls
///      (DEX swap + vault deposit), so the reactivity subscription `gasLimit` MUST be
///      set to at least `3_000_000` with `priorityFeePerGas >= 2 gwei` (2,000,000,000 wei).
///      See: Somnia Reactivity Precompile at `0x0000000000000000000000000000000000000100`.
contract YieldOptimizer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Reverted when the emergency ETH withdrawal fails.
    error YieldOptimizer__ETHWithdrawFailed();

    /// @dev Reverted when the contract is paused by the RiskGuard.
    error YieldOptimizer__Paused();

    /// @dev Reverted when `msg.sender` is not the reactivity precompile in a reactive callback.
    error YieldOptimizer__UnauthorizedCallback();

    /// @dev Reverted when a user tries to withdraw more shares than they hold.
    error YieldOptimizer__InsufficientShares();

    /// @dev Reverted when a zero-amount deposit or withdraw is attempted.
    error YieldOptimizer__ZeroAmount();

    /*//////////////////////////////////////////////////////////////
                     NETWORK ADDRESSES (IMMUTABLE)
    //////////////////////////////////////////////////////////////*/

    /// @notice The canonical Somnia Reactivity Precompile address.
    /// @dev This is the address that msg.sender will equal when a reactive
    ///      callback is invoked by the Somnia network after a subscribed event fires.
    address public constant SOMNIA_REACTIVITY_PRECOMPILE = 0x0000000000000000000000000000000000000100;

    /// @notice The address of the USDC token used as the base denomination for all operations.
    address public immutable usdc;

    /// @notice The address of the yield relayer whose reactive events this optimizer subscribes to.
    /// @dev The Somnia reactivity runtime will automatically invoke onYieldUpdated when this relayer emits YieldUpdated.
    address public immutable yieldRelayer;

    /// @notice The Uniswap V2-style DEX router used for token swaps during rebalances.
    IDEXRouter public immutable router;

    /*//////////////////////////////////////////////////////////////
                    RISKGUARD STATE (STORAGE-PACKED)
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether the optimizer is currently paused by the RiskGuard.
    /// @dev When `true`, all rebalancing and swap operations are blocked.
    bool public isPaused;

    /// @notice The maximum cumulative loss (in USDC) allowed before the RiskGuard
    ///         automatically pauses the contract.
    uint256 public maxLossThreshold;

    /// @notice Running total of cumulative losses incurred during rebalances.
    /// @dev When `cumulativeLoss >= maxLossThreshold`, the RiskGuard trips and sets
    ///      `isPaused = true`, emitting a `RiskGuardTripped` event.
    uint256 public cumulativeLoss;

    /// @notice The address of the yield farm where funds are currently deployed.
    /// @dev `address(0)` means funds are idle in USDC and not deposited in any farm.
    address public currentFarm;

    /*//////////////////////////////////////////////////////////////
                         FARM WHITELIST (H-03)
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps farm addresses to their whitelisted status.
    /// @dev Only whitelisted farms can be used as rebalance targets in `onYieldUpdated`.
    mapping(address => bool) public allowedFarms;

    /*//////////////////////////////////////////////////////////////
                     USER SHARE ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps each depositor to their internal share balance.
    /// @dev Shares represent a pro-rata claim on the optimizer's total portfolio value.
    mapping(address => uint256) public userShares;

    /// @notice Total supply of internal optimizer shares across all depositors.
    uint256 public totalOptimizerShares;

    /*//////////////////////////////////////////////////////////////
                       ACCOUNTING CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The minimum number of days funds must remain in a farm for a
    ///         rebalance to be considered economically worthwhile.
    /// @dev    Used to normalize the annual APY into a per-period yield estimate
    ///         before comparing against the one-time gas cost of a rebalance.
    ///         At 30 days, the optimizer asks: "Will 30 days of yield in the new
    ///         farm exceed the gas cost of moving there?"
    uint256 private constant HOLDING_PERIOD_DAYS = 30;

    /// @notice Estimated gas overhead for a full rebalance operation on Somnia.
    /// @dev    Somnia's gas model differs significantly from Ethereum mainnet:
    ///           - Cold SLOAD: ~1,000,000 gas (vs ~2,100 on Ethereum, ~476× more)
    ///           - LOG opcodes: ~13× Ethereum cost
    ///         A single `onYieldUpdated` execution involves 6+ cold SLOADs,
    ///         a DEX swap (cross-contract), and a farm deposit (cross-contract).
    ///         The default of 3_000_000 aligns with the subscription gasLimit
    ///         recommendation in the contract's architecture notes.
    ///         The owner can tune this value post-deployment via `setGasOverheadEstimate`
    ///         once real execution data is available from Somnia testnet.
    uint256 public gasOverheadEstimate = 3_000_000;

    /// @dev Basis-points denominator (10 000 = 100%).
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @dev 1.1× safety multiplier: numerator for the `(G + S) × 1.1` profitability check.
    uint256 private constant SAFETY_BUFFER_NUMERATOR = 11;
    uint256 private constant SAFETY_BUFFER_DENOMINATOR = 10;

    /// @dev Hardcoded ETH/USDC price for testnet profitability calculations.
    ///      In production, replace with a Chainlink ETH/USD oracle feed.
    ///      $3 000 per ETH, expressed in USDC's 6-decimal precision.
    uint256 private constant ETH_PRICE_USDC = 3000e6;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the owner updates the gas overhead estimate.
    /// @param oldEstimate The previous gas overhead estimate.
    /// @param newEstimate The new gas overhead estimate.
    event GasOverheadUpdated(uint256 oldEstimate, uint256 newEstimate);

    /// @notice Emitted after a successful rebalance execution.
    /// @param targetFarm The address of the yield farm that received the rebalanced funds.
    /// @param profitUSDC The net profit (in USDC) realised from the rebalance, after gas costs.
    /// @param gasSpent The total gas consumed by the rebalance operation.
    event OptimizerExecuted(address indexed targetFarm, uint256 profitUSDC, uint256 gasSpent);

    /// @notice Emitted when the RiskGuard trips due to cumulative losses exceeding the threshold.
    /// @param totalLoss The cumulative loss value that triggered the guard.
    event RiskGuardTripped(uint256 totalLoss);

    /// @notice Emitted when a user deposits USDC into the optimizer.
    /// @param user The depositor's address.
    /// @param assets The USDC amount deposited.
    /// @param shares The internal shares minted to the user.
    event Deposited(address indexed user, uint256 assets, uint256 shares);

    /// @notice Emitted when a user withdraws USDC from the optimizer.
    /// @param user The withdrawer's address.
    /// @param shares The internal shares burned.
    /// @param assets The USDC amount returned to the user.
    event Withdrawn(address indexed user, uint256 shares, uint256 assets);

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Prevents execution when the contract is paused.
    modifier whenNotPaused() {
        if (isPaused) revert YieldOptimizer__Paused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the Yield Optimizer with the required network addresses and risk parameters.
    /// @param _usdc The address of the USDC token contract.
    /// @param _yieldRelayer The address of the relayer whose `YieldUpdated` events are trusted.
    /// @param _router The Uniswap V2-style DEX router for executing swaps.
    /// @param _maxLossThreshold The maximum cumulative loss (in USDC) before RiskGuard pauses operations.
    constructor(address _usdc, address _yieldRelayer, address _router, uint256 _maxLossThreshold)
        Ownable(msg.sender)
    {
        usdc = _usdc;
        yieldRelayer = _yieldRelayer;
        router = IDEXRouter(_router);

        maxLossThreshold = _maxLossThreshold;
    }

    /*//////////////////////////////////////////////////////////////
                       USER DEPOSIT / WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits USDC into the optimizer and mints proportional internal shares.
    /// @dev Share calculation:
    ///      - First depositor: `shares = assets` (1:1 bootstrapping).
    ///      - Subsequent depositors: `shares = assets × totalOptimizerShares / portfolioValue`.
    ///      This ensures late depositors do not dilute early depositors' accrued yield.
    /// @param assets The amount of USDC to deposit.
    function deposit(uint256 assets) external whenNotPaused nonReentrant {
        if (assets == 0) revert YieldOptimizer__ZeroAmount();

        // --- 1. Snapshot portfolio value BEFORE the transfer ---
        uint256 currentPortfolioValue = _getPortfolioValue();

        // --- 2. Calculate shares to mint ---
        uint256 shares;
        if (totalOptimizerShares == 0) {
            shares = assets;
        } else {
            shares = (assets * totalOptimizerShares) / currentPortfolioValue;
        }
        require(shares > 0, "YieldOptimizer: zero shares");

        // --- 3. Pull USDC from the user ---
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), assets);

        // --- 4. Update state ---
        userShares[msg.sender] += shares;
        totalOptimizerShares += shares;

        emit Deposited(msg.sender, assets, shares);
    }

    /// @notice Burns internal shares and returns the proportional USDC value to the user.
    /// @param shares The number of internal shares to redeem.
    function withdraw(uint256 shares) external nonReentrant {
        if (shares == 0) revert YieldOptimizer__ZeroAmount();
        if (userShares[msg.sender] < shares) revert YieldOptimizer__InsufficientShares();

        // --- 1. Calculate USDC owed ---
        uint256 assetsOwed = (shares * _getPortfolioValue()) / totalOptimizerShares;

        // --- 2. Update state (checks-effects-interactions) ---
        userShares[msg.sender] -= shares;
        totalOptimizerShares -= shares;

        // --- 3. Liquidity check: pull shortfall from the farm if needed ---
        uint256 idleUSDC = IERC20(usdc).balanceOf(address(this));

        if (idleUSDC < assetsOwed && currentFarm != address(0)) {
            uint256 shortfall = assetsOwed - idleUSDC;

            // Convert USDC shortfall → farm shares using the farm's exchange rate
            uint256 farmTotalAssets = IYieldFarm(currentFarm).totalAssets();
            uint256 farmTotalSupply = IERC20(currentFarm).totalSupply();
            uint256 farmSharesNeeded = (shortfall * farmTotalSupply) / farmTotalAssets;

            IYieldFarm(currentFarm).redeem(farmSharesNeeded, address(this), address(this));
        }

        // --- 4. Cap assetsOwed to actual balance (absorbs rounding dust from farm redemption) ---
        uint256 actualBalance = IERC20(usdc).balanceOf(address(this));
        if (assetsOwed > actualBalance) {
            assetsOwed = actualBalance;
        }

        // --- 5. Transfer USDC to the user ---
        IERC20(usdc).safeTransfer(msg.sender, assetsOwed);

        emit Withdrawn(msg.sender, shares, assetsOwed);
    }

    /*//////////////////////////////////////////////////////////////
                       REACTIVE CALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Reactive callback invoked automatically by the Somnia reactivity precompile
    ///         (0x0000000000000000000000000000000000000100) when the subscribed YieldRelayer
    ///         emits a `YieldUpdated(uint256,address)` event.
    /// @dev Call chain:
    ///        1. Off-chain Keeper calls `YieldRelayer.pushYieldUpdate(apy, farm)`
    ///        2. YieldRelayer emits `YieldUpdated(apy, farm)`
    ///        3. Somnia's reactivity precompile detects the event (because YieldOptimizer
    ///           subscribed via `ISomniaReactivity.subscribe` in the deploy script)
    ///        4. Precompile calls this function with msg.sender == SOMNIA_REACTIVITY_PRECOMPILE
    ///      SECURITY: msg.sender is checked against SOMNIA_REACTIVITY_PRECOMPILE.
    ///      Any direct call from a non-precompile address will revert.
    ///      The profitability check normalizes the annualized newAPY into a HOLDING_PERIOD_DAYS-period yield before comparing it against the one-time gas + slippage cost of rebalancing. A rebalance is only executed if the expected yield over the holding period exceeds total costs with a 1.1× safety buffer.
    /// @param newAPY The updated annual percentage yield in basis points (e.g. 500 = 5.00%).
    /// @param targetFarm The address of the yield farm to rebalance into.
    function onYieldUpdated(uint256 newAPY, address targetFarm) external {
        // --- 1. Access control: only the Somnia reactivity precompile may call this ---
        // The YieldRelayer emits the event; Somnia routes it; the precompile calls this function.
        if (msg.sender != SOMNIA_REACTIVITY_PRECOMPILE) {
            revert YieldOptimizer__UnauthorizedCallback();
        }

        // --- 2. Farm whitelist (Audit H-03 fix) ---
        require(allowedFarms[targetFarm], "Farm not whitelisted");

        // --- 3. Circuit breaker ---
        if (isPaused) revert YieldOptimizer__Paused();

        // --- 4. Snapshot total portfolio value before rebalance (Audit M-04 fix) ---
        uint256 portfolioBefore = _getPortfolioValue();

        // --- 5. Profitability math ---
        // Normalize annual APY to a per-period yield estimate.
        // Formula: portfolioBefore * newAPY / BPS_DENOMINATOR / (365 / HOLDING_PERIOD_DAYS)
        // Simplified to avoid integer division precision loss:
        // = portfolioBefore * newAPY * HOLDING_PERIOD_DAYS / (BPS_DENOMINATOR * 365)
        uint256 deltaY = (portfolioBefore * newAPY * HOLDING_PERIOD_DAYS) / (BPS_DENOMINATOR * 365);

        // Estimate live slippage using current on-chain pool prices
        address targetAsset = IYieldFarm(targetFarm).asset();
        uint256 slippage = _estimateLiveSlippage(portfolioBefore, targetAsset);

        uint256 estimatedGasCost = gasOverheadEstimate * tx.gasprice;
        uint256 gasCostUSDC = (estimatedGasCost * ETH_PRICE_USDC) / 1e18;

        uint256 totalCostWithBuffer = ((gasCostUSDC + slippage) * SAFETY_BUFFER_NUMERATOR) / SAFETY_BUFFER_DENOMINATOR;

        if (deltaY <= totalCostWithBuffer) {
            // Not profitable — return gracefully without reverting.
            return;
        }

        // --- 6. Execute the rebalance ---
        // Capture gas remaining before rebalance execution for accurate gas accounting
        uint256 gasAtStart = gasleft();
        (uint256 profitUSDC, uint256 gasUsed, , uint256 portfolioAfter) = _executeRebalance(targetFarm, portfolioBefore);

        // Account for gas used outside _executeRebalance (the profitability check itself)
        uint256 totalGasUsed = gasUsed + (gasAtStart - gasleft());

        emit OptimizerExecuted(targetFarm, profitUSDC, totalGasUsed);

        // --- 7. RiskGuard: check for losses using full portfolio value (Audit M-04 fix) ---
        if (portfolioAfter < portfolioBefore) {
            uint256 loss = portfolioBefore - portfolioAfter;
            cumulativeLoss += loss;

            if (cumulativeLoss >= maxLossThreshold) {
                isPaused = true;
                emit RiskGuardTripped(cumulativeLoss);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL — REBALANCE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @param targetFarm The yield farm to rebalance funds into.
    function _executeRebalance(address targetFarm, uint256 portfolioBefore)
        internal
        returns (uint256 profitUSDC, uint256 gasUsed, uint256 gasAtExecStart, uint256 portfolioAfter)
    {
        gasAtExecStart = gasleft();
        // --- 1. Withdraw from current farm if funds are deployed ---
        address currentAsset;
        uint256 swapAmount;

        if (currentFarm != address(0)) {
            // Redeem all shares from the current vault
            currentAsset = IYieldFarm(currentFarm).asset();
            uint256 shares = IERC20(currentFarm).balanceOf(address(this));
            if (shares > 0) {
                IYieldFarm(currentFarm).redeem(shares, address(this), address(this));
            }
            swapAmount = IERC20(currentAsset).balanceOf(address(this));
        } else {
            // Funds are idle in USDC
            currentAsset = usdc;
            swapAmount = IERC20(usdc).balanceOf(address(this));
        }

        // --- 2. Determine target asset ---
        address targetAsset = IYieldFarm(targetFarm).asset();

        // --- 3. Swap if current asset ≠ target asset ---
        uint256 receivedAmount;

        if (currentAsset != targetAsset && swapAmount > 0) {
            // --- 3a. Routing: query factory for direct pair ---
            address factoryAddr = router.factory();
            address[] memory path;

            address directPair = IUniswapV2Factory(factoryAddr).getPair(currentAsset, targetAsset);

            if (directPair != address(0)) {
                // Direct pool exists → single-hop path
                path = new address[](2);
                path[0] = currentAsset;
                path[1] = targetAsset;
            } else {
                // No direct pool → multi-hop through USDC
                path = new address[](3);
                path[0] = currentAsset;
                path[1] = usdc;
                path[2] = targetAsset;
            }

            // --- 3b. Slippage protection: 1% tolerance from live reserves (Audit H-01 fix) ---
            uint256[] memory expectedAmounts = router.getAmountsOut(swapAmount, path);
            uint256 expectedOutput = expectedAmounts[expectedAmounts.length - 1];
            // minAmountOut = expectedOutput × 99 / 100 (1% slippage tolerance)
            uint256 minAmountOut = (expectedOutput * 99) / 100;

            // --- 3c. Exact approval (NOT type(uint256).max) ---
            IERC20(currentAsset).forceApprove(address(router), swapAmount);

            // --- 3d. Execute the swap ---
            uint256[] memory amounts = router.swapExactTokensForTokens(
                swapAmount,
                minAmountOut,
                path,
                address(this),
                block.timestamp + 300 // deadline = 5 minutes from now (Audit M-03 fix)
            );

            receivedAmount = amounts[amounts.length - 1];
        } else {
            // No swap needed — assets already match
            receivedAmount = swapAmount;
        }

        // --- 4. Deposit into target farm ---
        if (receivedAmount > 0) {
            // Exact approval for the target vault
            IERC20(targetAsset).forceApprove(targetFarm, receivedAmount);

            // Deposit and receive vault shares
            IYieldFarm(targetFarm).deposit(receivedAmount, address(this));
        }

        // --- 5. Update state ---
        currentFarm = targetFarm;

        // Emit is handled by the caller (onYieldUpdated) once gas and profit are known
        // Compute gas used by this execution
        gasUsed = gasAtExecStart - gasleft();

        // Compute net profit: portfolio value after deployment vs before
        portfolioAfter = _getPortfolioValue();
        profitUSDC = portfolioAfter > portfolioBefore ? portfolioAfter - portfolioBefore : 0;
    }

    /*//////////////////////////////////////////////////////////////
                     INTERNAL — PORTFOLIO VALUATION
    //////////////////////////////////////////////////////////////*/

    function _getPortfolioValue() internal view returns (uint256) {
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));

        if (currentFarm != address(0)) {
            uint256 shares = IERC20(currentFarm).balanceOf(address(this));
            if (shares > 0) {
                usdcBalance += (shares * IYieldFarm(currentFarm).totalAssets()) / IERC20(currentFarm).totalSupply();
            }
        }

        return usdcBalance;
    }

    /// @notice Estimates the slippage cost (in USDC) of swapping `amount` of USDC
    ///         through the DEX at current live pool prices.
    /// @dev    Calls router.getAmountsOut with a two-token path [usdc → targetAsset].
    ///         Slippage is expressed as the difference between the ideal output
    ///         (if price impact were zero) and the actual quoted output, converted back
    ///         to USDC terms using the quoted rate.
    ///         Returns 0 if the router or path cannot be queried (e.g. no pool exists).
    /// @param  amount     The USDC amount to estimate slippage for.
    /// @param  targetAsset The token address of the farm's underlying asset.
    /// @return slippageUSDC The estimated slippage cost in USDC (6 decimals).
    function _estimateLiveSlippage(uint256 amount, address targetAsset)
        internal
        view
        returns (uint256 slippageUSDC)
    {
        if (amount == 0 || targetAsset == usdc) {
            return 0;
        }

        address[] memory path = new address[](2);
        path[0] = usdc;
        path[1] = targetAsset;

        try router.getAmountsOut(amount, path) returns (uint256[] memory amounts) {
            if (amounts.length < 2 || amounts[1] == 0) return 0;

            // Ideal output if there were zero price impact:
            // idealOut = amount (since we're moving USDC→asset→USDC conceptually,
            // the round-trip cost approximates 2× one-way fee+impact).
            // Simpler: compare quoted output to a "perfect" output assuming spot price.
            // We use the quoted rate to back-compute USDC equivalent of output,
            // then take the difference from the input amount.

            // quotedRate: how many targetAsset tokens per USDC (scaled to 1e6)
            // priceImpact is implicitly captured in amounts[1] vs spot.

            // For a simple estimate: slippage ≈ amountIn - (amountOut_in_usdc)
            // We re-quote the reverse to get USDC back:
            address[] memory reversePath = new address[](2);
            reversePath[0] = targetAsset;
            reversePath[1] = usdc;

            try router.getAmountsOut(amounts[1], reversePath) returns (uint256[] memory reverseAmounts) {
                if (reverseAmounts.length < 2) return 0;
                uint256 roundTripUSDC = reverseAmounts[1];
                if (amount > roundTripUSDC) {
                    slippageUSDC = amount - roundTripUSDC;
                }
            } catch {
                return 0;
            }
        } catch {
            return 0;
        }
    }

    /*//////////////////////////////////////////////////////////////
                     ADMIN — CONFIGURATION (C-02, H-03)
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the gas overhead estimate used in rebalance profitability checks.
    /// @dev    Tune this value based on observed gas usage from Somnia testnet execution data.
    ///         Setting too low will allow unprofitable rebalances.
    ///         Setting too high will suppress profitable rebalances.
    /// @param _newEstimate New gas overhead in gas units (not wei). Typical range: 1_000_000–10_000_000.
    function setGasOverheadEstimate(uint256 _newEstimate) external onlyOwner {
        require(_newEstimate > 0, "YieldOptimizer: gas estimate must be > 0");
        emit GasOverheadUpdated(gasOverheadEstimate, _newEstimate);
        gasOverheadEstimate = _newEstimate;
    }

    function setFarmAllowed(address farm, bool allowed) external onlyOwner {
        allowedFarms[farm] = allowed;
    }

    /*//////////////////////////////////////////////////////////////
                   ADMIN — CIRCUIT BREAKER RESET (M-01)
    //////////////////////////////////////////////////////////////*/

    function unpause() external onlyOwner {
        isPaused = false;
    }

    function resetCumulativeLoss() external onlyOwner {
        cumulativeLoss = 0;
    }

    /*//////////////////////////////////////////////////////////////
                   ADMIN — EMERGENCY WITHDRAWALS (L-01)
    //////////////////////////////////////////////////////////////*/

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function emergencyWithdrawETH() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert YieldOptimizer__ETHWithdrawFailed();
    }
}
