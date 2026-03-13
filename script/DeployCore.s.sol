// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {YieldRelayer} from "../src/YieldRelayer.sol";
import {YieldOptimizer} from "../src/YieldOptimizer.sol";

/// @title DeployCore — The Application
/// @author Hash-Hokage
/// @notice Deploys the core Yield Optimizer architecture and subscribes to
///         Somnia Reactivity.
/// @dev Reads sandbox addresses from environment variables (output of DeployMocks),
///      deploys `YieldRelayer` and `YieldOptimizer`, then creates a reactivity
///      subscription on the Somnia Precompile at `0x0100`.
///
///      **Environment Variables Required:**
///      - `USDC_ADDRESS`       — Mock USDC deployed by DeployMocks
///      - `MOCK_FARM_ADDRESS`  — MockYieldFarm deployed by DeployMocks
///      - `ROUTER_ADDRESS`     — Mock DEX Router deployed by DeployMocks
///      - `PAYMASTER_ADDRESS`  — Paymaster for gas reimbursement
///
///      **Deployment Command (Somnia Testnet):**
///      ```bash
///      forge script script/DeployCore.s.sol \
///        --rpc-url https://api.infra.testnet.somnia.network \
///        --account deployer \
///        --sender <your-deployer-address> \
///        --gas-estimate-multiplier 200 \
///        --broadcast
///      ```
contract DeployCore is Script {
    /*//////////////////////////////////////////////////////////////
                          SOMNIA CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev The canonical Somnia Reactivity Precompile address.
    address constant REACTIVITY_PRECOMPILE = 0x0000000000000000000000000000000000000100;

    /// @dev The minimum STT balance required to activate a reactivity subscription.
    uint256 constant SUBSCRIPTION_DEPOSIT = 32 ether; // 32 STT

    /// @dev Maximum cumulative loss (in USDC) before the RiskGuard circuit breaker
    ///      pauses the optimizer. Set to 5,000 USDC.
    uint256 constant MAX_LOSS_THRESHOLD = 5_000e6;

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function run() external returns (address deployedYieldRelayer, address deployedYieldOptimizer) {
        // ─────────────────────────────────────────────────
        //  1. Read environment variables
        // ─────────────────────────────────────────────────
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address mockFarmAddress = vm.envAddress("MOCK_FARM_ADDRESS");
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");
        address paymasterAddress = vm.envAddress("PAYMASTER_ADDRESS");

        console.log("========================================");
        console.log("  DEPLOY CORE -- THE APPLICATION");
        console.log("========================================");
        console.log("");
        console.log("USDC:                ", usdcAddress);
        console.log("MockFarm:            ", mockFarmAddress);
        console.log("Router:              ", routerAddress);
        console.log("Paymaster:           ", paymasterAddress);
        console.log("Max Loss Threshold:  ", MAX_LOSS_THRESHOLD);
        console.log("");

        // ─────────────────────────────────────────────────
        //  2. Start broadcast (uses --account deployer keystore)
        // ─────────────────────────────────────────────────
        vm.startBroadcast();

        address deployer = msg.sender;
        console.log("Deployer:            ", deployer);
        console.log("Deployer balance:    ", deployer.balance);

        require(
            deployer.balance >= SUBSCRIPTION_DEPOSIT,
            "DeployCore: Deployer must hold >= 32 STT for subscription deposit"
        );

        // ─────────────────────────────────────────────────
        //  3. Deploy YieldRelayer
        // ─────────────────────────────────────────────────
        YieldRelayer yieldRelayer = new YieldRelayer(deployer);
        console.log("[DEPLOYED] YieldRelayer:      ", address(yieldRelayer));

        // ─────────────────────────────────────────────────
        //  4. Deploy YieldOptimizer
        // ─────────────────────────────────────────────────
        YieldOptimizer yieldOptimizer = new YieldOptimizer(
            usdcAddress,
            paymasterAddress,
            address(yieldRelayer), // trustedOracle
            routerAddress,
            MAX_LOSS_THRESHOLD
        );
        console.log("[DEPLOYED] YieldOptimizer:    ", address(yieldOptimizer));

        // ─────────────────────────────────────────────────
        //  5. Somnia Reactivity Subscription
        // ─────────────────────────────────────────────────
        // Note: The on-chain canonical Somnia Reactivity Precompile (0x0100)
        // requires the `subscribe(SubscriptionData)` signature, and handlers
        // must implement `onEvent(address,bytes32[],bytes)`.
        //
        // Because YieldOptimizer implements `onYieldUpdated(uint256,address)`
        // directly and verifies `msg.sender == trustedOracle`, it is designed
        // for an OFF-CHAIN subscription using the TypeScript SDK.
        // Therefore, we do not subscribe on-chain here.

        console.log("");
        console.log("--- Reactivity Subscription ---");
        console.log("YieldOptimizer verifies msg.sender == YieldRelayer.");
        console.log("Please use the @somnia-chain/reactivity TypeScript SDK");
        console.log("in your Node.js Keeper to watch YieldUpdated events and");
        console.log("push them directly to YieldOptimizer.onYieldUpdated().");

        // ─────────────────────────────────────────────────
        //  6. Stop broadcast
        // ─────────────────────────────────────────────────
        vm.stopBroadcast();

        // ─────────────────────────────────────────────────
        //  7. Summary
        // ─────────────────────────────────────────────────
        console.log("");
        console.log("========================================");
        console.log("  CORE DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Copy these into your .env/viemConfig.ts:");
        console.log("");
        console.log("  YIELD_RELAYER_ADDRESS=", address(yieldRelayer));
        console.log("  YIELD_OPTIMIZER_ADDRESS=", address(yieldOptimizer));
        console.log("");
        console.log("========================================");

        return (address(yieldRelayer), address(yieldOptimizer));
    }
}
