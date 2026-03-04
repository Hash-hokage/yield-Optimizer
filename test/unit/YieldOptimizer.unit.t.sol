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
                     UNIT TEST CONTRACT
//////////////////////////////////////////////////////////////*/

/// @title YieldOptimizer Unit Tests
/// @author Hash-Hokage
/// @notice Validates the profitable and unprofitable rebalance paths through `onYieldUpdated`.
contract YieldOptimizerUnitTest is Test {
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

    /// @dev Constants matching the values in YieldOptimizer.
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant FIXED_GAS_OVERHEAD = 50_000;

    /// @dev Test amounts.
    uint256 private constant INITIAL_USDC_BALANCE = 1_000_000e6; // 1M USDC
    uint256 private constant DEX_RESERVE_USDC = 1_000_000_000e6; // 1B USDC liquidity
    uint256 private constant DEX_RESERVE_TARGET = 1_000_000_000e6; // 1B target token liquidity (6 decimals)
    uint256 private constant MAX_LOSS_THRESHOLD = 1_000_000e6;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Re-declare event for `vm.expectEmit`.
    event OptimizerExecuted(
        address indexed targetFarm,
        uint256 profitUSDC,
        uint256 gasSpent
    );

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the optimizer and all mocks, seed balances and configure reserves.
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
        // Register a non-zero pair address so the optimizer detects a direct pool
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

        // --- 11. Set cached reserves on the optimizer (using new admin setter) ---
        optimizer.updateCachedReserves(DEX_RESERVE_USDC, DEX_RESERVE_TARGET);

        // --- 12. Whitelist the farm (Audit H-03) ---
        optimizer.setFarmAllowed(address(farm), true);

        // --- 13. Fund the optimizer with ETH for paymaster reimbursement ---
        vm.deal(address(optimizer), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    TEST — PROFITABLE REBALANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Simulates an ideal oracle update with a high APY that passes the profitability gate.
    /// @dev Verifies:
    ///      1. The swap completes (target token deposited into the farm).
    ///      2. The paymaster is reimbursed with ETH.
    ///      3. The `OptimizerExecuted` event is emitted with the correct target farm.
    function test_ExecuteRebalance_Profitable() public {
        // --- Arrange ---
        uint256 highAPY = 5000; // 50% in basis points → very large ΔY to exceed (G+S)×1.1
        uint256 paymasterBalanceBefore = paymaster.balance;

        // Use a very low gas price so the gas cost is negligible compared to ΔY
        vm.txGasPrice(1 wei);

        // --- Act ---
        // Expect the OptimizerExecuted event with the correct target farm
        // We check topic 1 (indexed targetFarm) and ignore data fields (profitUSDC, gasSpent)
        vm.expectEmit(true, false, false, false, address(optimizer));
        emit OptimizerExecuted(address(farm), 0, 0);

        // Call onYieldUpdated as the trusted oracle
        vm.prank(trustedOracle);
        optimizer.onYieldUpdated(highAPY, address(farm));

        // --- Assert ---

        // 1. Swap completed: optimizer's USDC balance should have decreased (swapped away)
        uint256 optimizerUsdcAfter = usdc.balanceOf(address(optimizer));
        assertEq(
            optimizerUsdcAfter,
            0,
            "Optimizer should have swapped all USDC"
        );

        // 2. Farm received the deposit: farm should hold target tokens
        uint256 farmTargetBalance = targetToken.balanceOf(address(farm));
        assertGt(
            farmTargetBalance,
            0,
            "Farm should hold target tokens after deposit"
        );

        // 3. Optimizer has shares in the farm
        uint256 optimizerShares = farm.balanceOf(address(optimizer));
        assertGt(optimizerShares, 0, "Optimizer should hold farm shares");

        // 4. Paymaster was reimbursed with ETH
        uint256 paymasterBalanceAfter = paymaster.balance;
        assertGt(
            paymasterBalanceAfter,
            paymasterBalanceBefore,
            "Paymaster should have received ETH reimbursement"
        );

        // 5. currentFarm is set to the target farm
        assertEq(
            optimizer.currentFarm(),
            address(farm),
            "currentFarm should be updated to target farm"
        );
    }

    /*//////////////////////////////////////////////////////////////
                   TEST — UNPROFITABLE REBALANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Simulates an oracle update where the fees outweigh the yield.
    /// @dev Verifies:
    ///      1. No swap is executed (USDC balance unchanged).
    ///      2. The function returns gracefully without reverting.
    ///      3. No state changes occur (currentFarm remains address(0)).
    function test_ExecuteRebalance_Unprofitable() public {
        // --- Arrange ---
        uint256 tinyAPY = 1; // 0.01% in basis points → negligible ΔY
        uint256 optimizerUsdcBefore = usdc.balanceOf(address(optimizer));
        uint256 paymasterBalanceBefore = paymaster.balance;

        // Use a high gas price so the gas cost dominates and ΔY <= (G+S) × 1.1
        vm.txGasPrice(100 gwei);

        // --- Act ---
        // Call onYieldUpdated as the trusted oracle — should return gracefully
        vm.prank(trustedOracle);
        optimizer.onYieldUpdated(tinyAPY, address(farm));

        // --- Assert ---

        // 1. USDC balance unchanged — no swap was executed
        uint256 optimizerUsdcAfter = usdc.balanceOf(address(optimizer));
        assertEq(
            optimizerUsdcAfter,
            optimizerUsdcBefore,
            "USDC balance should be unchanged (no swap)"
        );

        // 2. No farm shares — nothing was deposited
        uint256 optimizerShares = farm.balanceOf(address(optimizer));
        assertEq(optimizerShares, 0, "Optimizer should hold zero farm shares");

        // 3. currentFarm remains unset
        assertEq(
            optimizer.currentFarm(),
            address(0),
            "currentFarm should remain address(0)"
        );

        // 4. Paymaster balance unchanged — no reimbursement occurred
        uint256 paymasterBalanceAfter = paymaster.balance;
        assertEq(
            paymasterBalanceAfter,
            paymasterBalanceBefore,
            "Paymaster balance should be unchanged"
        );
    }
}
