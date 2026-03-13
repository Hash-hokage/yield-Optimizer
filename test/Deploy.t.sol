// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployMocks} from "../script/DeployMocks.s.sol";
import {DeployCore} from "../script/DeployCore.s.sol";
import {YieldOptimizer} from "../src/YieldOptimizer.sol";
import {YieldRelayer} from "../src/YieldRelayer.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockYieldFarm} from "../src/mocks/MockYieldFarm.sol";
import {IDEXRouter} from "../src/interfaces/IDEXRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockPrecompile
/// @notice Dummy contract deployed via `vm.etch` to the Somnia Reactivity Precompile
///         address so the `DeployCore` script's `subscribe` call does not revert.
contract MockPrecompile {
    fallback() external payable {}
}

/// @title DeployTest
/// @author Hash-Hokage
/// @notice Verifies that the modular deployment scripts
///         (`DeployMocks.s.sol` + `DeployCore.s.sol`) produce a valid, fully-wired ecosystem.
contract DeployTest is Test {
    /*//////////////////////////////////////////////////////////////
                          STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    DeployMocks public deployMocksScript;

    address public deployedUsdc;
    address public deployedTargetToken;
    address public deployedFactory;
    address public deployedMockDex;
    address public deployedMockFarm;
    address public deployedYieldRelayer;
    address public deployedYieldOptimizer;

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // --- 1. Mock the Somnia Reactivity Precompile ---
        vm.etch(0x0000000000000000000000000000000000000100, address(new MockPrecompile()).code);

        // --- 2. Fund the test contract so DeployCore can send 32 ETH to the precompile ---
        vm.deal(address(this), 100 ether);

        // --- 3. Instantiate the DeployMocks script ---
        deployMocksScript = new DeployMocks();
    }

    /*//////////////////////////////////////////////////////////////
               HELPER — RUN BOTH SCRIPTS SEQUENTIALLY
    //////////////////////////////////////////////////////////////*/

    /// @dev Runs DeployMocks → sets env vars → runs DeployCore.
    function _runBothScripts() internal {
        (deployedUsdc, deployedTargetToken, deployedFactory, deployedMockDex, deployedMockFarm) =
            deployMocksScript.run();

        vm.setEnv("USDC_ADDRESS", vm.toString(deployedUsdc));
        vm.setEnv("MOCK_FARM_ADDRESS", vm.toString(deployedMockFarm));
        vm.setEnv("ROUTER_ADDRESS", vm.toString(deployedMockDex));
        vm.setEnv("PAYMASTER_ADDRESS", "0x1111111111111111111111111111111111111111");

        DeployCore deployCoreScript = new DeployCore();
        (deployedYieldRelayer, deployedYieldOptimizer) = deployCoreScript.run();
    }

    /*//////////////////////////////////////////////////////////////
         TEST 1 — DeployMocks outputs valid, non-zero addresses
    //////////////////////////////////////////////////////////////*/

    /// @notice Runs DeployMocks only and validates all 5 outputs.
    function test_DeployMocks_AllAddressesNonZero() public {
        (deployedUsdc, deployedTargetToken, deployedFactory, deployedMockDex, deployedMockFarm) =
            deployMocksScript.run();

        assertTrue(deployedUsdc != address(0), "USDC address is zero");
        assertTrue(deployedTargetToken != address(0), "TargetToken address is zero");
        assertTrue(deployedFactory != address(0), "Factory address is zero");
        assertTrue(deployedMockDex != address(0), "DEX address is zero");
        assertTrue(deployedMockFarm != address(0), "MockFarm address is zero");

        // Verify seeded reserves
        MockDEX mockDex = MockDEX(deployedMockDex);
        bytes32 pairKey = _pairKey(deployedUsdc, deployedTargetToken);
        assertEq(mockDex.reserves(pairKey, deployedUsdc), 100_000e6, "USDC reserve should be 100k");
        assertEq(mockDex.reserves(pairKey, deployedTargetToken), 100_000e18, "TGT reserve should be 100k");

        // Verify MockFarm's underlying asset is the TargetToken
        assertEq(MockYieldFarm(deployedMockFarm).asset(), deployedTargetToken, "MockFarm asset should be TGT");
    }

    /*//////////////////////////////////////////////////////////////
       TEST 2 — DeployCore wires YieldOptimizer constructor correctly
    //////////////////////////////////////////////////////////////*/

    /// @notice Runs both scripts and asserts that YieldOptimizer's immutable
    ///         addresses match the mock ecosystem outputs.
    function test_DeployCore_WiresOptimizerCorrectly() public {
        _runBothScripts();

        YieldOptimizer optimizer = YieldOptimizer(payable(deployedYieldOptimizer));

        assertEq(optimizer.usdc(), deployedUsdc, "Optimizer usdc() mismatch");
        assertEq(optimizer.trustedOracle(), deployedYieldRelayer, "Optimizer trustedOracle() should be YieldRelayer");
        assertEq(address(optimizer.router()), deployedMockDex, "Optimizer router() mismatch");
    }

    /*//////////////////////////////////////////////////////////////
       TEST 3 — DeployCore outputs non-zero YieldRelayer + Optimizer
    //////////////////////////////////////////////////////////////*/

    /// @notice Runs both scripts and validates core contract addresses are non-zero.
    function test_DeployCore_OutputsNonZero() public {
        _runBothScripts();

        assertTrue(deployedYieldRelayer != address(0), "YieldRelayer address is zero");
        assertTrue(deployedYieldOptimizer != address(0), "YieldOptimizer address is zero");

        // Verify liquidity is reachable through the optimizer's router
        IDEXRouter dexRouter = IDEXRouter(deployedMockDex);
        address[] memory path = new address[](2);
        path[0] = deployedUsdc;
        path[1] = deployedTargetToken;

        uint256[] memory amounts = dexRouter.getAmountsOut(1_000e6, path);
        assertTrue(amounts.length == 2, "Expected 2-element amounts array");
        assertTrue(amounts[1] > 0, "Expected non-zero output from seeded liquidity");
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
