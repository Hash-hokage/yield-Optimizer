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
        factory.setPair(
            address(usdc),
            address(targetToken),
            makeAddr("usdc-tgt-pair")
        );
        dex.setFactory(address(factory));

        // --- 6. Deploy mock yield farm with the target token as underlying ---
        farm = new MockYieldFarm(address(targetToken));

        // --- 7. Deploy the YieldOptimizer ---
        optimizer = new YieldOptimizer(
            address(usdc),
            paymaster,
            trustedOracle,
            address(dex),
            MAX_LOSS_THRESHOLD
        );

        // --- 8. Seed USDC into the optimizer ---
        usdc.mint(address(optimizer), INITIAL_USDC_BALANCE);

        // --- 9. Configure DEX reserves ---
        dex.setReserves(
            address(usdc),
            address(targetToken),
            DEX_RESERVE_USDC,
            DEX_RESERVE_TARGET
        );

        // --- 10. Pre-fund the DEX with target tokens so it can fulfil swaps ---
        targetToken.mint(address(dex), DEX_RESERVE_TARGET);

        // --- 11. Set cached reserves on the optimizer ---
        vm.store(
            address(optimizer),
            bytes32(uint256(4)),
            bytes32(DEX_RESERVE_USDC)
        );
        vm.store(
            address(optimizer),
            bytes32(uint256(5)),
            bytes32(DEX_RESERVE_TARGET)
        );

        // --- 12. Fund the optimizer with ETH for paymaster reimbursement ---
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
        vm.expectRevert(
            YieldOptimizer.YieldOptimizer__UnauthorizedCallback.selector
        );
        optimizer.onYieldUpdated(maliciousAPY, address(farm));
    }

    /*//////////////////////////////////////////////////////////////
          TEST — SLIPPAGE PROTECTION (FRONT-RUNNING ATTACK)
    //////////////////////////////////////////////////////////////*/

    /// @notice Simulates a sandwich / front-running attack by draining MockDEX liquidity
    ///         so the actual swap output falls below the optimizer's `minAmountOut`.
    /// @dev Attack narrative:
    ///      1. Attacker front-runs the oracle callback by performing a massive swap on the
    ///         DEX, removing almost all target-token liquidity from the pool.
    ///      2. The optimizer's cached reserves still reflect the original deep liquidity,
    ///         so it computes a generous `minAmountOut`.
    ///      3. When the actual swap executes against the drained pool the output is far
    ///         below `minAmountOut` → the DEX router reverts with `InsufficientOutputAmount`.
    ///
    ///      This validates the 1% slippage tolerance guard in `_executeRebalance`.
    function testRevert_SlippageProtection() public {
        // --- Arrange: simulate front-running by draining target-token liquidity ---

        // Slash the DEX's target-token reserves to ~0.1% of original (simulates attacker's
        // giant buy that sucks out almost all TGT liquidity).
        uint256 drainedTargetReserve = DEX_RESERVE_TARGET / 1000; // 1M from 1B
        dex.setReserves(
            address(usdc),
            address(targetToken),
            DEX_RESERVE_USDC * 10, // Attacker dumped massive USDC in
            drainedTargetReserve // Almost no TGT left in pool
        );

        // The optimizer still has stale cached reserves (set in setUp) which assume deep
        // liquidity, so its `minAmountOut` will be ~99% of the original expected output.
        // The real pool will produce a fraction of that.

        uint256 highAPY = 5000; // 50% — comfortably passes the profitability gate
        vm.txGasPrice(1 wei); // Minimise gas cost so profitability gate passes

        // --- Act + Assert ---
        vm.prank(trustedOracle);
        vm.expectRevert(MockDEX.MockDEX__InsufficientOutputAmount.selector);
        optimizer.onYieldUpdated(highAPY, address(farm));
    }

    /*//////////////////////////////////////////////////////////////
        TEST — RISKGUARD CIRCUIT BREAKER (CUMULATIVE LOSS ATTACK)
    //////////////////////////////////////////////////////////////*/

    /// @notice Forces sequential unprofitable rebalances until cumulative losses exceed
    ///         `maxLossThreshold`, proving the circuit breaker activates.
    /// @dev Attack narrative:
    ///      An attacker (or buggy oracle) repeatedly triggers rebalances where each swap
    ///      incurs a loss.  After enough rounds, `cumulativeLoss >= maxLossThreshold`
    ///      trips the RiskGuard and sets `isPaused = true`, blocking all further operations.
    ///
    ///      Mechanism:
    ///      - Each rebalance swaps the optimizer's entire USDC balance into TGT.
    ///      - After the swap the optimizer's USDC balance drops to 0 → the full balance
    ///        is recorded as a loss.
    ///      - We verify the breaker trips and any subsequent callback is rejected.
    function test_RiskGuard_CircuitBreaker() public {
        // --- Arrange ---
        uint256 highAPY = 5000;
        vm.txGasPrice(1 wei);

        // We will trigger losses in a loop. Each rebalance converts all USDC → TGT,
        // so the USDC loss per round ≈ INITIAL_USDC_BALANCE.
        // maxLossThreshold = 1_000_000e6 = INITIAL_USDC_BALANCE, so a single full-loss
        // round should trip the breaker.

        // Sanity: contract is NOT paused before we begin
        assertFalse(optimizer.isPaused(), "Should not be paused initially");

        // --- Act ---
        // Expect the RiskGuardTripped event when cumulative loss hits threshold
        vm.expectEmit(false, false, false, true, address(optimizer));
        emit RiskGuardTripped(INITIAL_USDC_BALANCE);

        vm.prank(trustedOracle);
        optimizer.onYieldUpdated(highAPY, address(farm));

        // --- Assert ---

        // 1. isPaused must be true — circuit breaker has tripped
        assertTrue(
            optimizer.isPaused(),
            "isPaused should be true after breaker trips"
        );

        // 2. cumulativeLoss must be at or above the threshold
        assertGe(
            optimizer.cumulativeLoss(),
            MAX_LOSS_THRESHOLD,
            "cumulativeLoss should meet or exceed maxLossThreshold"
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
