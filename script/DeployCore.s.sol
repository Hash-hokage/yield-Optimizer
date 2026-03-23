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
///      deploys `YieldRelayer` and `YieldOptimizer`.
///
///      **Environment Variables Required:**
///      - `USDC_ADDRESS`       — Mock USDC deployed by DeployMocks
///      - `MOCK_FARM_ADDRESS`  — MockYieldFarm deployed by DeployMocks
///      - `ROUTER_ADDRESS`     — Real DEX Router or address(0) for local tests
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
        address routerAddress = vm.envOr("ROUTER_ADDRESS", address(0));

        console.log("========================================");
        console.log("  DEPLOY CORE -- THE APPLICATION");
        console.log("========================================");
        console.log("");
        console.log("USDC:                ", usdcAddress);
        console.log("MockFarm:            ", mockFarmAddress);
        console.log("Router:              ", routerAddress);
        console.log("Max Loss Threshold:  ", MAX_LOSS_THRESHOLD);
        console.log("");

        // ─────────────────────────────────────────────────
        //  2. Start broadcast (uses --account deployer keystore)
        // ─────────────────────────────────────────────────
        address deployer = msg.sender;
        console.log("Deployer:            ", deployer);
        console.log("Deployer balance:    ", deployer.balance);

        // MOCK PRECOMPILE LOCALLY: Forge script simulates locally before broadcasting.
        // It will revert with "call to non-contract" if the precompile address has no code.
        // We etch a dummy block that returns `1` (uint256) so simulation handles the subscribe() call.
        vm.etch(REACTIVITY_PRECOMPILE, hex"600160005260206000f3");

        vm.startBroadcast(deployer);

        require(
            deployer.balance >= SUBSCRIPTION_DEPOSIT + 1 ether,
            "DeployCore: Deployer must hold >= 33 STT (32 for subscription deposit + 1 for gas)"
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
            address(yieldRelayer), // yieldRelayer
            routerAddress,
            MAX_LOSS_THRESHOLD
        );
        console.log("[DEPLOYED] YieldOptimizer:    ", address(yieldOptimizer));

        // ─────────────────────────────────────────────────
        //  4b. Fund YieldOptimizer with 32 STT
        // ─────────────────────────────────────────────────
        // YieldOptimizer must hold >= 32 STT to be the subscription owner.
        // It calls subscribe() on itself, so its own balance is checked by the precompile.
        (bool funded,) = address(yieldOptimizer).call{value: SUBSCRIPTION_DEPOSIT}("");
        require(funded, "DeployCore: Failed to fund YieldOptimizer with 32 STT");
        console.log("[FUNDED]   YieldOptimizer funded with 32 STT");

        // ─────────────────────────────────────────────────
        //  5. Somnia Reactivity Subscription
        // ─────────────────────────────────────────────────
        console.log("");
        console.log("--- Creating Reactivity Subscription via YieldOptimizer ---");
        console.log("YieldOptimizer will self-subscribe so it is the subscription owner.");
        console.log("Ensure YieldOptimizer holds >= 32 STT before calling this.");

        // YieldOptimizer calls subscribe on itself — it becomes the subscription owner.
        // handlerGasLimit = 3_000_000 for a complex handler (swap + farm deposit).
        yieldOptimizer.createReactivitySubscription(3_000_000);

        console.log("[SUBSCRIBED] Subscription ID:", yieldOptimizer.subscriptionId());
        console.log("[SUBSCRIBED] YieldOptimizer registered as handler for YieldRelayer.YieldUpdated");

        // ─────────────────────────────────────────────────
        //  5b. Whitelist the MockYieldFarm
        // ─────────────────────────────────────────────────
        // _onEvent checks allowedFarms[targetFarm] and silently returns if false.
        // The mapping starts empty — if this is not done at deploy time, every reactive
        // callback will wake up and quietly do nothing with no error or revert.
        yieldOptimizer.setFarmAllowed(mockFarmAddress, true);
        console.log("[WHITELISTED] MockYieldFarm approved as rebalance target:", mockFarmAddress);

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
