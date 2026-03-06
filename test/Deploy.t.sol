// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {YieldOptimizer} from "../src/YieldOptimizer.sol";
import {YieldRelayer} from "../src/YieldRelayer.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {IDEXRouter} from "../src/interfaces/IDEXRouter.sol";

/// @title MockPrecompile
/// @notice Dummy contract deployed via `vm.etch` to the Somnia Reactivity Precompile
///         address so the deployment script's `subscribe` call does not revert.
contract MockPrecompile {
    fallback() external payable {}
}

/// @title DeployTest
/// @author Hash-Hokage
/// @notice Verifies that the deterministic sandbox deployment script
///         (`script/Deploy.s.sol`) produces a valid, fully-wired ecosystem.
contract DeployTest is Test {
    /*//////////////////////////////////////////////////////////////
                          STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    Deploy public deployScript;

    address public deployedUsdc;
    address public deployedTargetToken;
    address public deployedMockDex;
    address public deployedYieldRelayer;
    address public deployedYieldOptimizer;

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // --- 1. Mock the Somnia Reactivity Precompile ---
        // The deployment script calls `subscribe` on 0x0100 with 32 ETH.
        // Without code at that address, the low-level `call` would succeed on
        // an empty account, but we etch real bytecode to be safe and deterministic.
        vm.etch(0x0000000000000000000000000000000000000100, address(new MockPrecompile()).code);

        // --- 2. Set environment variable the script expects ---
        vm.setEnv("PAYMASTER_ADDRESS", "0x1111111111111111111111111111111111111111");

        // --- 3. Fund the test contract so the script can send 32 ETH to the precompile ---
        vm.deal(address(this), 100 ether);

        // --- 4. Instantiate the deployment script ---
        deployScript = new Deploy();
    }

    /*//////////////////////////////////////////////////////////////
                      TEST — DEPLOYMENT SANDBOX
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes the full deployment script and asserts the final
    ///         state of every deployed contract and seeded liquidity pool.
    function test_DeploymentSandbox() public {
        // --- Execute the deployment script ---
        (deployedUsdc, deployedTargetToken, deployedMockDex, deployedYieldRelayer, deployedYieldOptimizer) =
            deployScript.run();

        // ─────────────────────────────────────────────────
        //  Assertion 1: No zero addresses
        // ─────────────────────────────────────────────────
        assertTrue(deployedUsdc != address(0), "USDC address is zero");
        assertTrue(deployedTargetToken != address(0), "TargetToken address is zero");
        assertTrue(deployedMockDex != address(0), "MockDEX address is zero");
        assertTrue(deployedYieldRelayer != address(0), "YieldRelayer address is zero");
        assertTrue(deployedYieldOptimizer != address(0), "YieldOptimizer address is zero");

        // ─────────────────────────────────────────────────
        //  Assertion 2: YieldOptimizer wiring
        // ─────────────────────────────────────────────────
        YieldOptimizer optimizer = YieldOptimizer(payable(deployedYieldOptimizer));

        assertEq(optimizer.usdc(), deployedUsdc, "Optimizer's usdc() should match deployed Mock USDC");

        assertEq(
            optimizer.trustedOracle(),
            deployedYieldRelayer,
            "Optimizer's trustedOracle() should match deployed YieldRelayer"
        );

        assertEq(address(optimizer.router()), deployedMockDex, "Optimizer's router() should match deployed MockDEX");

        // ─────────────────────────────────────────────────
        //  Assertion 3: Seeded liquidity verification
        // ─────────────────────────────────────────────────
        // Verify the MockDEX has the expected 100_000 / 100_000 reserves
        // by querying `getAmountsOut` for a small test amount.
        IDEXRouter dexRouter = IDEXRouter(deployedMockDex);

        address[] memory path = new address[](2);
        path[0] = deployedUsdc;
        path[1] = deployedTargetToken;

        // Swap 1,000 USDC (1_000e6) through the seeded pool
        uint256 testAmountIn = 1_000e6;
        uint256[] memory amounts = dexRouter.getAmountsOut(testAmountIn, path);

        // With 100k/100k reserves and 0.3% fee, output should be > 0
        assertTrue(amounts.length == 2, "Expected 2-element amounts array");
        assertTrue(amounts[1] > 0, "Expected non-zero output from seeded liquidity");

        // Verify the reserves are reasonable by checking the MockDEX directly
        MockDEX mockDex = MockDEX(deployedMockDex);
        bytes32 pairKey = _pairKey(deployedUsdc, deployedTargetToken);

        uint256 reserveUSDC = mockDex.reserves(pairKey, deployedUsdc);
        uint256 reserveTarget = mockDex.reserves(pairKey, deployedTargetToken);

        assertEq(reserveUSDC, 100_000e6, "USDC reserve should be 100,000");
        assertEq(reserveTarget, 100_000e18, "Target reserve should be 100,000");

        console.log("All deployment sandbox assertions passed!");
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Mirrors MockDEX._pairKey() to derive the reserve mapping key.
    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1));
    }
}
