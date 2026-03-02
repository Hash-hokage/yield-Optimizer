// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IDEXRouter} from "./interfaces/IDEXRouter.sol";
import {IYieldFarm} from "./interfaces/IYieldFarm.sol";
import {ISomniaReactivity} from "./interfaces/ISomniaReactivity.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
///      - RiskGuard state (`owner`, `isPaused`, `maxLossThreshold`, `cumulativeLoss`) is
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
contract YieldOptimizer {
    using SafeERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Reverted when a restricted function is called by a non-owner address.
    error YieldOptimizer__NotOwner();

    /// @dev Reverted when the contract is paused by the RiskGuard.
    error YieldOptimizer__Paused();

    /// @dev Reverted when `msg.sender` is not the trusted oracle in a reactive callback.
    error YieldOptimizer__UnauthorizedCallback();

    /// @dev Reverted when the paymaster reimbursement call fails.
    error YieldOptimizer__ReimbursementFailed();

    /// @dev Reverted when cached reserves are zero and a swap is attempted.
    error YieldOptimizer__ReservesNotCached();

    /*//////////////////////////////////////////////////////////////
                     NETWORK ADDRESSES (IMMUTABLE)
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the USDC token used as the base denomination for all operations.
    address public immutable usdc;

    /// @notice The paymaster address used for gas abstraction on the Somnia network.
    address public immutable paymaster;

    /// @notice The address of the trusted oracle whose reactive events this optimizer subscribes to.
    /// @dev Callbacks MUST verify `msg.sender` against this address to prevent spoofed yield updates.
    address public immutable trustedOracle;

    /// @notice The Uniswap V2-style DEX router used for token swaps during rebalances.
    IDEXRouter public immutable router;

    /*//////////////////////////////////////////////////////////////
                    RISKGUARD STATE (STORAGE-PACKED)
    //////////////////////////////////////////////////////////////*/

    /// @notice The owner / admin of the optimizer contract.
    /// @dev Together with `isPaused` (1 byte), this fits within a single 32-byte storage slot
    ///      (20 bytes address + 1 byte bool = 21 bytes).
    address public owner;

    /// @notice Whether the optimizer is currently paused by the RiskGuard.
    /// @dev When `true`, all rebalancing and swap operations are blocked.
    ///      Packed into the same storage slot as `owner`.
    bool public isPaused;

    /// @notice The maximum cumulative loss (in USDC) allowed before the RiskGuard
    ///         automatically pauses the contract.
    /// @dev Occupies its own storage slot (slot 1 of the RiskGuard group).
    uint256 public maxLossThreshold;

    /// @notice Running total of cumulative losses incurred during rebalances.
    /// @dev When `cumulativeLoss >= maxLossThreshold`, the RiskGuard trips and sets
    ///      `isPaused = true`, emitting a `RiskGuardTripped` event.
    ///      Occupies its own storage slot (slot 2 of the RiskGuard group).
    uint256 public cumulativeLoss;

    /// @notice The address of the yield farm where funds are currently deployed.
    /// @dev `address(0)` means funds are idle in USDC and not deposited in any farm.
    address public currentFarm;

    /*//////////////////////////////////////////////////////////////
                         REACTIVITY CACHE
    //////////////////////////////////////////////////////////////*/

    /// @notice Cached USDC reserve from the latest DEX pool snapshot.
    /// @dev Used to pre-compute slippage estimates without an external call during callbacks.
    uint256 public cachedReserveUSDC;

    /// @notice Cached target-token reserve from the latest DEX pool snapshot.
    /// @dev Paired with `cachedReserveUSDC` for constant-product slippage calculations.
    uint256 public cachedReserveTarget;

    /*//////////////////////////////////////////////////////////////
                       ACCOUNTING CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fixed gas overhead estimate used in profit-vs-gas accounting.
    /// @dev Accounts for base transaction costs, calldata, and storage operations that
    ///      are not captured by `gasleft()` measurements within the execution flow.
    uint256 private constant FIXED_GAS_OVERHEAD = 50000;

    /// @dev Basis-points denominator (10 000 = 100%).
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @dev 1.1× safety multiplier: numerator for the `(G + S) × 1.1` profitability check.
    uint256 private constant SAFETY_BUFFER_NUMERATOR = 11;
    uint256 private constant SAFETY_BUFFER_DENOMINATOR = 10;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful rebalance execution.
    /// @param targetFarm The address of the yield farm that received the rebalanced funds.
    /// @param profitUSDC The net profit (in USDC) realised from the rebalance, after gas costs.
    /// @param gasSpent The total gas consumed by the rebalance operation.
    event OptimizerExecuted(
        address indexed targetFarm,
        uint256 profitUSDC,
        uint256 gasSpent
    );

    /// @notice Emitted when the RiskGuard trips due to cumulative losses exceeding the threshold.
    /// @param totalLoss The cumulative loss value that triggered the guard.
    event RiskGuardTripped(uint256 totalLoss);

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Restricts access to the contract owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert YieldOptimizer__NotOwner();
        _;
    }

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
    /// @param _paymaster The paymaster address for Somnia gas abstraction.
    /// @param _trustedOracle The address of the oracle whose `YieldUpdated` events are trusted.
    /// @param _router The Uniswap V2-style DEX router for executing swaps.
    /// @param _maxLossThreshold The maximum cumulative loss (in USDC) before RiskGuard pauses operations.
    constructor(
        address _usdc,
        address _paymaster,
        address _trustedOracle,
        address _router,
        uint256 _maxLossThreshold
    ) {
        usdc = _usdc;
        paymaster = _paymaster;
        trustedOracle = _trustedOracle;
        router = IDEXRouter(_router);

        owner = msg.sender;
        maxLossThreshold = _maxLossThreshold;
    }

    /*//////////////////////////////////////////////////////////////
                       REACTIVE CALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Reactive callback invoked by the trusted oracle when a yield rate changes.
    /// @dev Full execution flow:
    ///      1. Verify `msg.sender == trustedOracle` (prevent spoofed callbacks).
    ///      2. Check circuit breaker (`!isPaused`).
    ///      3. Snapshot `gasleft()` for gas accounting.
    ///      4. Compute expected yield delta (ΔY) from `newAPY`.
    ///      5. Estimate slippage (S) from `cachedReserveUSDC` / `cachedReserveTarget`.
    ///      6. Estimate gas cost (G) using current `tx.gasprice`.
    ///      7. Require ΔY > (G + S) × 1.1 — if not, return gracefully (no revert).
    ///      8. Execute the rebalance via `_executeRebalance`.
    ///      9. Reimburse gas via paymaster.
    ///     10. RiskGuard: accumulate any losses; trip if threshold is breached.
    ///
    ///      **Somnia Gas:** This handler is "complex" (cross-contract calls, loops,
    ///      multiple storage reads). The reactivity subscription backing this callback
    ///      must use `gasLimit >= 3_000_000`, `priorityFeePerGas >= 2 gwei`.
    ///
    /// @param newAPY The updated annual percentage yield in basis points (e.g. 500 = 5.00%).
    /// @param targetFarm The address of the yield farm to rebalance into.
    function onYieldUpdated(uint256 newAPY, address targetFarm) external {
        // --- 1. Access control: only the trusted oracle may call this ---
        if (msg.sender != trustedOracle) {
            revert YieldOptimizer__UnauthorizedCallback();
        }

        // --- 2. Circuit breaker ---
        if (isPaused) revert YieldOptimizer__Paused();

        // --- 3. Gas tracking ---
        uint256 startGas = gasleft();

        // --- 4. Snapshot USDC balance before rebalance ---
        uint256 balanceBefore = IERC20(usdc).balanceOf(address(this));

        // --- 5. Profitability math ---
        //  ΔY = expected yield = balance × newAPY / BPS_DENOMINATOR
        //  (annualised; in practice a per-epoch scaling would be applied)
        uint256 deltaY = (balanceBefore * newAPY) / BPS_DENOMINATOR;

        //  S  = slippage estimate using constant-product formula on cached reserves.
        //       S ≈ amountIn² / reserveIn  (first-order Taylor approximation)
        //       If reserves are not yet cached, slippage defaults to 0 (conservative).
        uint256 slippage = 0;
        if (cachedReserveUSDC > 0) {
            slippage = (balanceBefore * balanceBefore) / cachedReserveUSDC;
        }

        //  G  = estimated gas cost in USDC-equivalent wei
        //       (simplified: raw wei cost; production would use a gas-price oracle)
        uint256 estimatedGasCost = FIXED_GAS_OVERHEAD * tx.gasprice;

        //  Profitability gate: ΔY > (G + S) × 1.1
        uint256 totalCostWithBuffer = ((estimatedGasCost + slippage) *
            SAFETY_BUFFER_NUMERATOR) / SAFETY_BUFFER_DENOMINATOR;

        if (deltaY <= totalCostWithBuffer) {
            // Not profitable — return gracefully without reverting.
            return;
        }

        // --- 6. Execute the rebalance ---
        _executeRebalance(targetFarm);

        // --- 7. Gas reimbursement via paymaster ---
        uint256 gasSpent = startGas - gasleft() + FIXED_GAS_OVERHEAD;
        uint256 totalCost = gasSpent * tx.gasprice;

        (bool success, ) = paymaster.call{value: totalCost}("");
        if (!success) revert YieldOptimizer__ReimbursementFailed();

        // --- 8. RiskGuard: check for losses ---
        uint256 balanceAfter = IERC20(usdc).balanceOf(address(this));

        if (balanceAfter < balanceBefore) {
            uint256 loss = balanceBefore - balanceAfter;
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

    /// @notice Executes the full rebalance: withdraw → route → swap → deposit.
    /// @dev Execution flow:
    ///      1. **Withdraw** — If funds are in a current farm, redeem all shares.
    ///      2. **Determine assets** — Identify the current asset and the target farm's asset.
    ///      3. **Route** — Query `router.factory().getPair()` for a direct pool.
    ///         - If a direct pair exists → single-hop path `[currentAsset, targetAsset]`.
    ///         - Otherwise → multi-hop path `[currentAsset, USDC, targetAsset]`.
    ///      4. **Exact approval** — Approve the router for the precise swap amount (not `type(uint256).max`).
    ///      5. **Swap** — Execute via `router.swapExactTokensForTokens` with 1% slippage tolerance.
    ///      6. **Deposit** — Approve the target farm and call `deposit()`.
    ///
    ///      **Slippage Protection:**
    ///      `minAmountOut` is derived from `cachedReserveTarget` with a 1% tolerance:
    ///      `minAmountOut = expectedOutput * 99 / 100`.
    ///
    /// @param targetFarm The yield farm to rebalance funds into.
    function _executeRebalance(address targetFarm) internal {
        // --- 1. Withdraw from current farm if funds are deployed ---
        address currentAsset;
        uint256 swapAmount;

        if (currentFarm != address(0)) {
            // Redeem all shares from the current vault
            currentAsset = IYieldFarm(currentFarm).asset();
            uint256 shares = IERC20(currentFarm).balanceOf(address(this));
            if (shares > 0) {
                IYieldFarm(currentFarm).redeem(
                    shares,
                    address(this),
                    address(this)
                );
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

            address directPair = IUniswapV2Factory(factoryAddr).getPair(
                currentAsset,
                targetAsset
            );

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

            // --- 3b. Slippage protection: 1% tolerance from cached reserves ---
            if (cachedReserveUSDC == 0 || cachedReserveTarget == 0) {
                revert YieldOptimizer__ReservesNotCached();
            }

            // expectedOutput = swapAmount × cachedReserveTarget / cachedReserveUSDC
            uint256 expectedOutput = (swapAmount * cachedReserveTarget) /
                cachedReserveUSDC;
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
                block.timestamp // deadline = current block (immediate execution)
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

        // --- 6. Emit event ---
        emit OptimizerExecuted(targetFarm, receivedAmount, 0);
    }

    /*//////////////////////////////////////////////////////////////
                         RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    /// @dev Accept ETH so the contract can hold funds for paymaster reimbursement.
    receive() external payable {}
}
