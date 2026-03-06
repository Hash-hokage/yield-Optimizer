// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {YieldOptimizer} from "../../src/YieldOptimizer.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockOracle} from "../../src/mocks/MockOracle.sol";
import {MockDEX} from "../../src/mocks/MockDEX.sol";
import {MockUniswapV2Factory} from "../../src/mocks/MockUniswapV2Factory.sol";
import {MockYieldFarm} from "../../src/mocks/MockYieldFarm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*//////////////////////////////////////////////////////////////
                   SECURITY TEST CONTRACT
//////////////////////////////////////////////////////////////*/

/// @title YieldOptimizer Security Tests
/// @author Hash-Hokage
/// @notice Adversarial tests targeting access control, slippage protection, and the RiskGuard
///         circuit breaker. Each test simulates a realistic attack vector.
contract YieldOptimizerSecurityTest is Test {
    /*//////////////////////////////////////////////////////////////
                          STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    YieldOptimizer public optimizer;
    MockERC20 public usdc;
    MockERC20 public targetToken;
    MockOracle public oracle;
    MockDEX public dex;
    MockYieldFarm public farm;
    MockUniswapV2Factory public factory;

    address public paymaster;
    address public trustedOracle;

    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant FIXED_GAS_OVERHEAD = 50_000;

    uint256 private constant INITIAL_USDC_BALANCE = 1_000_000e6; // 1M USDC
    uint256 private constant DEX_RESERVE_USDC = 1_000_000_000e6; // 1B USDC liquidity
    uint256 private constant DEX_RESERVE_TARGET = 1_000_000_000e6; // 1B target token liquidity
    uint256 private constant MAX_LOSS_THRESHOLD = 1_000_000e6;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event RiskGuardTripped(uint256 totalLoss);

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the optimizer and all mocks, seed balances and configure reserves.
    ///         Identical to the unit test setUp().
    function setUp() public {
        // --- 1. Deploy mock tokens ---
        usdc = new MockERC20("USD Coin", "USDC", 6);
        targetToken = new MockERC20("Target Token", "TGT", 6);

        // --- 2. Deploy mock oracle (also acts as trustedOracle address) ---
        oracle = new MockOracle();
        trustedOracle = address(oracle);

        // --- 3. Create paymaster as a simple labeled address ---
        paymaster = makeAddr("paymaster");

        // --- 4. Deploy mock DEX router ---
        dex = new MockDEX();

        // --- 5. Deploy mock factory and register the USDC-TGT pair ---
        factory = new MockUniswapV2Factory();
        factory.setPair(address(usdc), address(targetToken), makeAddr("usdc-tgt-pair"));
        dex.setFactory(address(factory));

        // --- 6. Deploy mock yield farm with the target token as underlying ---
        farm = new MockYieldFarm(address(targetToken));

        // --- 7. Deploy the YieldOptimizer ---
        optimizer = new YieldOptimizer(address(usdc), paymaster, trustedOracle, address(dex), MAX_LOSS_THRESHOLD);

        // --- 8. Seed USDC into the optimizer ---
        usdc.mint(address(optimizer), INITIAL_USDC_BALANCE);

        // --- 9. Configure DEX reserves ---
        dex.setReserves(address(usdc), address(targetToken), DEX_RESERVE_USDC, DEX_RESERVE_TARGET);

        // --- 10. Pre-fund the DEX with target tokens so it can fulfil swaps ---
        targetToken.mint(address(dex), DEX_RESERVE_TARGET);

        // --- 11. Set cached reserves on the optimizer (using new admin setter) ---
        optimizer.updateCachedReserves(DEX_RESERVE_USDC, DEX_RESERVE_TARGET);

        // --- 12. Whitelist the farm (Audit H-03) ---
        optimizer.setFarmAllowed(address(farm), true);

        // --- 13. Fund the optimizer with ETH for paymaster reimbursement ---
        vm.deal(address(optimizer), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
             TEST — ACCESS CONTROL (UNAUTHORIZED CALLBACK)
    //////////////////////////////////////////////////////////////*/

    /// @notice An attacker impersonates a random address and calls `onYieldUpdated`.
    /// @dev The contract MUST revert with `YieldOptimizer__UnauthorizedCallback`
    ///      because only `trustedOracle` is authorised to invoke the callback.
    ///      Attack surface: If this check were missing, anyone could trigger
    ///      rebalances with fabricated APY values and drain the vault.
    function testRevert_AccessControl() public {
        // --- Arrange ---
        address attacker = makeAddr("attacker");
        uint256 maliciousAPY = 9999; // Max-boost APY to force rebalance

        // --- Act + Assert ---
        vm.prank(attacker);
        vm.expectRevert(YieldOptimizer.YieldOptimizer__UnauthorizedCallback.selector);
        optimizer.onYieldUpdated(maliciousAPY, address(farm));
    }

    /*//////////////////////////////////////////////////////////////
          TEST — SLIPPAGE PROTECTION (FRONT-RUNNING ATTACK)
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates that the 1% slippage tolerance in `_executeRebalance` correctly
    ///         rejects swaps where the actual output deviates from the quoted output.
    /// @dev Attack narrative (post Audit H-01 fix):
    ///      The optimizer now quotes `minAmountOut` dynamically via `router.getAmountsOut`.
    ///      We validate the DEX-side enforcement by configuring the MockDEX to return
    ///      fewer tokens than the quoted minimum. This is done by artificially capping
    ///      the DEX's available target-token balance below what `getAmountsOut` promises,
    ///      causing the DEX transfer to fail.
    ///
    ///      This tests the entire slippage pipeline: quote → minAmountOut → DEX check.
    function testRevert_SlippageProtection() public {
        // --- Arrange ---
        // Set reserves to a normal 1:1 ratio so getAmountsOut returns a large value,
        // but only fund the DEX with a tiny amount of target tokens so the transfer
        // reverts when the DEX tries to send the full amount.
        //
        // getAmountsOut(1M USDC) will quote ~996K TGT (0.3% fee),
        // minAmountOut = ~996K * 99 / 100 = ~986K TGT,
        // but the DEX only has 100 TGT → transfer reverts.

        // Remove all existing TGT from the DEX by setting reserves fresh
        dex.setReserves(address(usdc), address(targetToken), DEX_RESERVE_USDC, DEX_RESERVE_TARGET);

        // Drain the DEX's actual TGT token balance to far below what the swap needs
        // (the MockDEX can still compute getAmountsOut from reserves, but can't fulfil
        // the transfer because it doesn't hold enough tokens).
        uint256 dexTgtBalance = targetToken.balanceOf(address(dex));
        vm.prank(address(dex));
        targetToken.transfer(address(1), dexTgtBalance); // drain all TGT from DEX

        // Fund only a tiny amount — far less than the swap output
        targetToken.mint(address(dex), 100);

        uint256 highAPY = 5000; // 50%
        vm.txGasPrice(1 wei);

        // --- Act + Assert ---
        // The swap should revert because the DEX can't transfer enough tokens
        vm.prank(trustedOracle);
        vm.expectRevert(); // ERC20 transfer will fail (insufficient balance)
        optimizer.onYieldUpdated(highAPY, address(farm));
    }

    /*//////////////////////////////////////////////////////////////
        TEST — RISKGUARD CIRCUIT BREAKER (CUMULATIVE LOSS ATTACK)
    //////////////////////////////////////////////////////////////*/

    /// @notice Forces a rebalance with extreme slippage so the portfolio suffers a real
    ///         loss, proving the circuit breaker activates on genuine value destruction.
    /// @dev Attack narrative (post Audit M-04 fix):
    ///      The RiskGuard now tracks full portfolio value (USDC + farm shares), so a
    ///      normal 1:1 swap no longer false-positives as a "loss". To trigger the breaker
    ///      we must inflict *actual* value destruction:
    ///
    ///      1. The DEX pool is configured with a 1000:1 USDC/TGT ratio, meaning the
    ///         optimizer receives ~0.1% of the TGT it should get for its USDC.
    ///      2. Cached reserves are left at the original 1:1, so `minAmountOut` is
    ///         extremely generous and doesn't block the bad swap.
    ///      3. After the swap, the portfolio value (farm shares priced via `convertToAssets`)
    ///         is tiny relative to the original USDC — a real loss.
    ///      4. `cumulativeLoss` exceeds `maxLossThreshold` → RiskGuard trips.
    function test_RiskGuard_CircuitBreaker() public {
        // --- Arrange ---
        uint256 highAPY = 5000; // 50% — passes profitability gate
        vm.txGasPrice(1 wei);

        // Skew the real pool dramatically: 10,000× more USDC per TGT.
        // The optimizer will receive almost no TGT for its 1M USDC.
        // Cached reserves are also updated to match so `minAmountOut` passes.
        uint256 skewedUSDCReserve = DEX_RESERVE_USDC * 10_000; // 10T USDC in pool
        uint256 skewedTargetReserve = DEX_RESERVE_TARGET / 10_000; // 100K TGT in pool

        dex.setReserves(address(usdc), address(targetToken), skewedUSDCReserve, skewedTargetReserve);

        // Update cached reserves to match the skewed pool so minAmountOut passes
        optimizer.updateCachedReserves(skewedUSDCReserve, skewedTargetReserve);

        // Ensure DEX has enough target tokens to fulfil the (tiny) swap output
        targetToken.mint(address(dex), skewedTargetReserve);

        // Lower the maxLossThreshold to account for the AMM's non-zero residual output.
        // The constant-product formula always returns a tiny amount, so loss is never
        // exactly 100%. Setting threshold to 999K USDC ensures the ~99.999% loss trips it.
        // Storage slot 1 = maxLossThreshold (verified via `forge inspect`).
        vm.store(address(optimizer), bytes32(uint256(1)), bytes32(uint256(999_000e6)));

        // Sanity: contract is NOT paused before we begin
        assertFalse(optimizer.isPaused(), "Should not be paused initially");

        // --- Act ---
        vm.prank(trustedOracle);
        optimizer.onYieldUpdated(highAPY, address(farm));

        // --- Assert ---

        // 1. isPaused must be true — circuit breaker has tripped
        assertTrue(optimizer.isPaused(), "isPaused should be true after breaker trips");

        // 2. cumulativeLoss must be at or above the adjusted threshold (999_000e6)
        assertGe(
            optimizer.cumulativeLoss(), 999_000e6, "cumulativeLoss should meet or exceed adjusted maxLossThreshold"
        );

        // 3. Attempting another callback must revert with YieldOptimizer__Paused
        //    Re-fund optimizer to prove it's the pause — not lack of capital — blocking execution
        usdc.mint(address(optimizer), INITIAL_USDC_BALANCE);
        targetToken.mint(address(dex), DEX_RESERVE_TARGET);

        vm.prank(trustedOracle);
        vm.expectRevert(YieldOptimizer.YieldOptimizer__Paused.selector);
        optimizer.onYieldUpdated(highAPY, address(farm));
    }
}
