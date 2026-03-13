// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockUniswapV2Factory} from "../src/mocks/MockUniswapV2Factory.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockYieldFarm} from "../src/mocks/MockYieldFarm.sol";

/// @title DeployMocks — The Sandbox
/// @author Hash-Hokage
/// @notice Deploys the isolated mock ecosystem for local / testnet testing.
/// @dev Deploys Mock Tokens (USDC + TGT), a Mock AMM (Factory + DEX Router),
///      seeds initial liquidity, and deploys a MockYieldFarm.
///
///      Run this script FIRST, then feed the output addresses into DeployCore.
///
///      **Deployment Command (Somnia Testnet):**
///      ```bash
///      forge script script/DeployMocks.s.sol \
///        --rpc-url https://api.infra.testnet.somnia.network \
///        --account deployer \
///        --sender <your-deployer-address> \
///        --gas-estimate-multiplier 200 \
///        --broadcast
///      ```
contract DeployMocks is Script {
    function run()
        external
        returns (
            address deployedUsdc,
            address deployedTargetToken,
            address deployedFactory,
            address deployedDex,
            address deployedMockFarm
        )
    {
        console.log("========================================");
        console.log("  DEPLOY MOCKS -- THE SANDBOX");
        console.log("========================================");
        console.log("");

        // ─────────────────────────────────────────────────
        //  1. Start broadcast (uses --account deployer keystore)
        // ─────────────────────────────────────────────────
        vm.startBroadcast();

        address deployer = msg.sender;
        console.log("Deployer:            ", deployer);
        console.log("");

        // ─────────────────────────────────────────────────
        //  2. Deploy Mock Tokens
        // ─────────────────────────────────────────────────
        MockERC20 usdc = new MockERC20("Mock USDC", "USDC", 6);
        MockERC20 targetToken = new MockERC20("Target Farm Token", "TGT", 18);

        // Mint 1,000,000 of each to the deployer
        usdc.mint(deployer, 1_000_000e6);
        targetToken.mint(deployer, 1_000_000e18);

        console.log("[DEPLOYED] Mock USDC:         ", address(usdc));
        console.log("[DEPLOYED] TargetToken (TGT): ", address(targetToken));

        // ─────────────────────────────────────────────────
        //  3. Deploy Mock AMM (Factory + DEX Router)
        // ─────────────────────────────────────────────────
        MockUniswapV2Factory mockFactory = new MockUniswapV2Factory();
        MockDEX mockDex = new MockDEX();
        mockDex.setFactory(address(mockFactory));

        console.log("[DEPLOYED] Mock Factory:      ", address(mockFactory));
        console.log("[DEPLOYED] Mock DEX Router:   ", address(mockDex));

        // ─────────────────────────────────────────────────
        //  4. Seed Liquidity (100k USDC / 100k TGT)
        // ─────────────────────────────────────────────────
        mockDex.setReserves(address(usdc), address(targetToken), 100_000e6, 100_000e18);
        console.log("[SEEDED]   Liquidity 100k/100k on Mock DEX");

        // ─────────────────────────────────────────────────
        //  5. Deploy MockYieldFarm
        // ─────────────────────────────────────────────────
        MockYieldFarm mockFarm = new MockYieldFarm(address(targetToken));
        console.log("[DEPLOYED] MockYieldFarm:     ", address(mockFarm));

        // ─────────────────────────────────────────────────
        //  6. Stop broadcast
        // ─────────────────────────────────────────────────
        vm.stopBroadcast();

        // ─────────────────────────────────────────────────
        //  7. Summary — copy into .env for DeployCore
        // ─────────────────────────────────────────────────
        console.log("");
        console.log("========================================");
        console.log("  SANDBOX DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Copy these into your .env for DeployCore:");
        console.log("");
        console.log("  USDC_ADDRESS=", address(usdc));
        console.log("  TARGET_TOKEN_ADDRESS=", address(targetToken));
        console.log("  FACTORY_ADDRESS=", address(mockFactory));
        console.log("  ROUTER_ADDRESS=", address(mockDex));
        console.log("  MOCK_FARM_ADDRESS=", address(mockFarm));
        console.log("");
        console.log("========================================");

        return (address(usdc), address(targetToken), address(mockFactory), address(mockDex), address(mockFarm));
    }
}
