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

/// @title Retail Mechanics Unit Tests
/// @author Hash-Hokage
/// @notice Validates the new deposit/withdraw share-based accounting system
///         introduced in the retail-facing vault upgrade.
/// @dev Tests three critical paths:
///      1. Deposit math — first + subsequent deposits with yield accrual.
///      2. Withdraw (idle) — withdrawing when USDC is sitting in the contract.
///      3. Withdraw (shortfall) — withdrawing when USDC is deployed in a farm.
contract RetailMechanicsTest is Test {
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
    address public yieldRelayer;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 private constant MAX_LOSS_THRESHOLD = 1_000_000e6;
    uint256 private constant DEX_RESERVE_USDC = 1_000_000_000e6;
    uint256 private constant DEX_RESERVE_TARGET = 1_000_000_000e6;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 shares, uint256 assets);

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // --- 1. Deploy mock tokens (both 6 decimals for clean math) ---
        usdc = new MockERC20("USD Coin", "USDC", 6);
        targetToken = new MockERC20("Target Token", "TGT", 6);

        // --- 2. Deploy mock oracle ---
        oracle = new MockOracle();
        yieldRelayer = address(oracle);

        // --- 3. Paymaster ---
        paymaster = makeAddr("paymaster");

        // --- 4. Deploy mock DEX ---
        dex = new MockDEX();
        factory = new MockUniswapV2Factory();
        factory.setPair(address(usdc), address(targetToken), makeAddr("usdc-tgt-pair"));
        dex.setFactory(address(factory));
        dex.setReserves(address(usdc), address(targetToken), DEX_RESERVE_USDC, DEX_RESERVE_TARGET);
        targetToken.mint(address(dex), DEX_RESERVE_TARGET);

        // --- 5. Deploy mock yield farm (underlying = targetToken) ---
        farm = new MockYieldFarm(address(targetToken));

        // --- 6. Deploy the YieldOptimizer ---
        optimizer = new YieldOptimizer(address(usdc), yieldRelayer, address(dex), MAX_LOSS_THRESHOLD);

        // --- 7. Configure optimizer ---
        optimizer.setFarmAllowed(address(farm), true);
        vm.deal(address(optimizer), 10 ether);

        // --- 8. Fund test users ---
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);

        // --- 9. Approve optimizer for both users ---
        vm.prank(alice);
        usdc.approve(address(optimizer), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(optimizer), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                   TEST 1 — DEPOSIT MATH
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies that deposit correctly mints shares:
    ///         - First deposit: 1:1 (shares == assets).
    ///         - Subsequent deposit: pro-rata based on current portfolio value.
    function test_Deposit_MintsCorrectShares() public {
        // --- Alice deposits 10,000 USDC (first depositor → 1:1) ---
        uint256 aliceDeposit = 10_000e6;

        vm.expectEmit(true, false, false, true, address(optimizer));
        emit Deposited(alice, aliceDeposit, aliceDeposit);

        vm.prank(alice);
        optimizer.deposit(aliceDeposit);

        assertEq(optimizer.userShares(alice), aliceDeposit, "Alice should get 1:1 shares on first deposit");
        assertEq(optimizer.totalOptimizerShares(), aliceDeposit, "Total shares should equal first deposit");
        assertEq(usdc.balanceOf(address(optimizer)), aliceDeposit, "Optimizer should hold Alice's USDC");

        // --- Simulate yield: donate 5,000 USDC directly to the optimizer ---
        // After yield, portfolio = 15,000 USDC, total shares = 10,000
        // Share price = 15,000 / 10,000 = 1.5 USDC/share
        uint256 yieldAmount = 5_000e6;
        usdc.mint(address(optimizer), yieldAmount);
        uint256 portfolioAfterYield = usdc.balanceOf(address(optimizer)); // 15,000e6

        // --- Bob deposits 15,000 USDC ---
        // Expected shares = 15,000 * 10,000 / 15,000 = 10,000 shares
        uint256 bobDeposit = 15_000e6;
        uint256 expectedBobShares = (bobDeposit * optimizer.totalOptimizerShares()) / portfolioAfterYield;
        assertEq(expectedBobShares, 10_000e6, "Sanity: expected Bob shares == 10,000");

        vm.expectEmit(true, false, false, true, address(optimizer));
        emit Deposited(bob, bobDeposit, expectedBobShares);

        vm.prank(bob);
        optimizer.deposit(bobDeposit);

        assertEq(optimizer.userShares(bob), expectedBobShares, "Bob shares should be pro-rata");
        assertEq(optimizer.totalOptimizerShares(), aliceDeposit + expectedBobShares, "Total shares should sum");

        // --- Verify Alice's share value has appreciated ---
        // Portfolio = 30,000 USDC, total shares = 20,000
        // Alice's 10,000 shares are worth 10,000 * 30,000 / 20,000 = 15,000 USDC
        uint256 aliceValue =
            (optimizer.userShares(alice) * usdc.balanceOf(address(optimizer))) / optimizer.totalOptimizerShares();
        assertEq(aliceValue, 15_000e6, "Alice's shares should be worth 15,000 USDC (original + yield)");
    }

    /*//////////////////////////////////////////////////////////////
                   TEST 2 — WITHDRAW (IDLE USDC)
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies withdrawal when USDC is idle in the contract (no farm).
    function test_Withdraw_Idle() public {
        // --- Alice deposits 10,000 USDC ---
        uint256 depositAmount = 10_000e6;
        vm.prank(alice);
        optimizer.deposit(depositAmount);

        uint256 aliceShares = optimizer.userShares(alice);
        assertEq(aliceShares, depositAmount, "Shares should be 1:1");

        // --- Alice withdraws all shares ---
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        vm.expectEmit(true, false, false, true, address(optimizer));
        emit Withdrawn(alice, aliceShares, depositAmount);

        vm.prank(alice);
        optimizer.withdraw(aliceShares);

        // --- Assertions ---
        assertEq(optimizer.userShares(alice), 0, "Alice shares should be zero after full withdrawal");
        assertEq(optimizer.totalOptimizerShares(), 0, "Total shares should be zero");
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + depositAmount, "Alice should receive back her full deposit");
        assertEq(usdc.balanceOf(address(optimizer)), 0, "Optimizer should have zero USDC");
    }

    /*//////////////////////////////////////////////////////////////
          TEST 3 — WITHDRAW (SHORTFALL / FARM LIQUIDATION)
    //////////////////////////////////////////////////////////////*/

    /// @notice Directly deposits optimizer USDC into a USDC-denominated farm,
    ///         then has a user withdraw, triggering shortfall liquidation.
    /// @dev We use a USDC-denominated MockYieldFarm to isolate the withdraw()
    ///      shortfall logic without cross-asset swap complexity.
    function test_Withdraw_Shortfall_Liquidation() public {
        // --- Step 1: Deploy a USDC-denominated farm ---
        MockYieldFarm usdcFarm = new MockYieldFarm(address(usdc));
        optimizer.setFarmAllowed(address(usdcFarm), true);

        // --- Step 2: Alice deposits 10,000 USDC ---
        uint256 depositAmount = 10_000e6;
        vm.prank(alice);
        optimizer.deposit(depositAmount);

        uint256 aliceShares = optimizer.userShares(alice);
        assertEq(aliceShares, depositAmount, "Shares should be 1:1");

        // --- Step 3: Simulate funds being deployed into the USDC farm ---
        // The owner manually moves the optimizer's USDC into the farm.
        // This mimics what _executeRebalance does for a same-asset deposit.
        uint256 optimizerBalance = usdc.balanceOf(address(optimizer));
        assertEq(optimizerBalance, depositAmount, "Optimizer should hold 10k USDC");

        // Approve and deposit directly via the test (as the optimizer)
        vm.startPrank(address(optimizer));
        usdc.approve(address(usdcFarm), optimizerBalance);
        usdcFarm.deposit(optimizerBalance, address(optimizer));
        vm.stopPrank();

        // Set currentFarm via vm.store — slot 3 per `forge inspect` storage layout.
        bytes32 currentFarmSlot = bytes32(uint256(3));
        vm.store(address(optimizer), currentFarmSlot, bytes32(uint256(uint160(address(usdcFarm)))));
        assertEq(optimizer.currentFarm(), address(usdcFarm), "currentFarm should be usdcFarm");

        // Verify state: optimizer has 0 idle USDC, but holds farm shares
        assertEq(usdc.balanceOf(address(optimizer)), 0, "Optimizer idle USDC should be 0");
        uint256 optimizerFarmShares = usdcFarm.balanceOf(address(optimizer));
        assertEq(optimizerFarmShares, depositAmount, "Optimizer should hold farm shares equal to deposit");

        // --- Step 4: Alice withdraws all shares → triggers farm liquidation ---
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        optimizer.withdraw(aliceShares);

        // --- Assertions ---
        assertEq(optimizer.userShares(alice), 0, "Alice shares should be zero");
        assertEq(optimizer.totalOptimizerShares(), 0, "Total shares should be zero");

        // Alice should receive her full USDC (1:1 farm, at most 1 wei rounding dust lost)
        uint256 aliceReceived = usdc.balanceOf(alice) - aliceUsdcBefore;
        assertGe(aliceReceived, depositAmount - 1, "Alice should receive ~10,000 USDC from shortfall liquidation");

        // Farm shares should be fully redeemed
        uint256 remainingFarmShares = usdcFarm.balanceOf(address(optimizer));
        assertEq(remainingFarmShares, 0, "All farm shares should be redeemed");
    }
}
