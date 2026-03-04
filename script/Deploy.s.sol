// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {YieldRelayer} from "../src/YieldRelayer.sol";
import {YieldOptimizer} from "../src/YieldOptimizer.sol";

/// @title Deploy
/// @author Hash-Hokage
/// @notice Foundry deployment script for the Somnia Yield Optimizer architecture.
/// @dev Deploys `YieldRelayer` and `YieldOptimizer`, then creates a reactivity
///      subscription on the Somnia Precompile at `0x0100` so that `YieldUpdated`
///      events emitted by the Relayer are automatically routed to the Optimizer's
///      `onYieldUpdated` callback.
///
///      **Authentication:**
///      Uses Foundry's encrypted keystore (`--account`). NEVER store
///      private keys in plaintext, .env files, or source code.
///
///      **Environment Variables Required (addresses only):**
///      - `USDC_ADDRESS`      — Address of the USDC token on Somnia Testnet
///      - `PAYMASTER_ADDRESS` — Address of the paymaster for gas reimbursement
///      - `ROUTER_ADDRESS`    — Address of the Uniswap V2-style DEX router
///
///      **Deployment Command (Somnia Testnet):**
///      ```bash
///      forge script script/Deploy.s.sol \
///        --rpc-url https://api.infra.testnet.somnia.network \
///        --account <your-keystore-account-name> \
///        --sender <your-deployer-address> \
///        --gas-estimate-multiplier 200 \
///        --broadcast
///      ```
///
///      The `--gas-estimate-multiplier 200` (2×) is **required** because Foundry's
///      gas estimation does not match Somnia's gas model (cold SLOAD ~476× costlier,
///      LOG ~13× costlier). Increase to `300` if deployment reverts with out-of-gas.
///
///      **Somnia Reactivity Integration:**
///      After deploying both contracts, the script calls `subscribe(address, bytes32)`
///      on the Reactivity Precompile (`0x0100`), passing the `YieldRelayer` address and
///      the `keccak256("YieldUpdated(uint256,address)")` event signature. Exactly
///      32 STT is attached to satisfy Somnia's minimum subscription balance requirement.
contract Deploy is Script {
    /*//////////////////////////////////////////////////////////////
                          SOMNIA CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev The canonical Somnia Reactivity Precompile address.
    ///      All on-chain subscription management goes through this address.
    ///      See: https://docs.somnia.network/developer/reactivity
    address constant REACTIVITY_PRECOMPILE =
        0x0000000000000000000000000000000000000100;

    /// @dev The minimum STT balance required to activate a reactivity subscription.
    ///      The subscription owner (deployer EOA) must hold >= 32 STT.
    ///      This value is sent with the `subscribe` call.
    uint256 constant SUBSCRIPTION_DEPOSIT = 32 ether; // 32 STT (18 decimals, same as ether)

    /// @dev Maximum cumulative loss (in USDC) before the RiskGuard circuit breaker
    ///      pauses the optimizer. Set to 1,000 USDC (6 decimals) by default.
    ///      Adjust based on risk tolerance before production deployment.
    uint256 constant MAX_LOSS_THRESHOLD = 1_000e6; // 1,000 USDC

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Main deployment entry point.
    /// @dev Uses Foundry's `--account` keystore for signing. Reads contract
    ///      addresses from environment variables. NEVER reads private keys.
    function run() external {
        // ─────────────────────────────────────────────────
        //  1. Load environment variables (addresses only)
        // ─────────────────────────────────────────────────
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address paymasterAddress = vm.envAddress("PAYMASTER_ADDRESS");
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");

        console.log("========================================");
        console.log("  SOMNIA YIELD OPTIMIZER -- DEPLOYMENT");
        console.log("========================================");
        console.log("");
        console.log("USDC:                ", usdcAddress);
        console.log("Paymaster:           ", paymasterAddress);
        console.log("Router:              ", routerAddress);
        console.log("Max Loss Threshold:  ", MAX_LOSS_THRESHOLD);
        console.log("");

        // ─────────────────────────────────────────────────
        //  2. Start broadcast (keystore signer via --account)
        // ─────────────────────────────────────────────────
        //    Foundry's encrypted keystore provides the signing key.
        //    Pass --account <name> --sender <address> on the CLI.
        vm.startBroadcast();

        address deployer = msg.sender;
        console.log("Deployer:            ", deployer);
        console.log("Deployer balance:    ", deployer.balance);

        // Sanity check: deployer must hold >= 32 STT for the subscription deposit
        require(
            deployer.balance >= SUBSCRIPTION_DEPOSIT,
            "Deploy: Deployer must hold >= 32 STT for subscription deposit"
        );

        // ─────────────────────────────────────────────────
        //  3. Deploy YieldRelayer
        // ─────────────────────────────────────────────────
        //    The deployer (Keeper EOA) is the initial owner,
        //    meaning only this address can call pushYieldUpdate().
        YieldRelayer yieldRelayer = new YieldRelayer(deployer);

        console.log("[DEPLOYED] YieldRelayer:  ", address(yieldRelayer));

        // ─────────────────────────────────────────────────
        //  4. Deploy YieldOptimizer
        // ─────────────────────────────────────────────────
        //    trustedOracle = address(yieldRelayer)
        //    This means YieldOptimizer will only accept
        //    onYieldUpdated() calls from the Relayer contract.
        YieldOptimizer yieldOptimizer = new YieldOptimizer(
            usdcAddress,
            paymasterAddress,
            address(yieldRelayer), // trustedOracle
            routerAddress,
            MAX_LOSS_THRESHOLD
        );

        console.log("[DEPLOYED] YieldOptimizer:", address(yieldOptimizer));

        // ─────────────────────────────────────────────────
        //  5. Somnia Reactivity — Create Subscription
        // ─────────────────────────────────────────────────
        //    Subscribe the YieldOptimizer to the YieldRelayer's
        //    `YieldUpdated(uint256,address)` event via the
        //    Somnia Reactivity Precompile at 0x0100.
        //
        //    32 STT is attached to satisfy the minimum balance
        //    requirement for on-chain subscriptions.

        // Calculate the event signature hash
        bytes32 eventSig = keccak256("YieldUpdated(uint256,address)");

        console.log("");
        console.log("--- Reactivity Subscription ---");
        console.log("Precompile:          ", REACTIVITY_PRECOMPILE);
        console.log("Emitter (Relayer):   ", address(yieldRelayer));
        console.log("Handler (Optimizer): ", address(yieldOptimizer));
        console.log("Event signature:     ");
        console.logBytes32(eventSig);
        console.log("Deposit:              32 STT");

        // Execute the subscription call on the precompile
        // The subscribe(address, bytes32) function registers interest in a
        // specific event from a specific contract. The attached 32 STT
        // funds the subscription so validators will process callbacks.
        (bool success, ) = REACTIVITY_PRECOMPILE.call{
            value: SUBSCRIPTION_DEPOSIT
        }(
            abi.encodeWithSignature(
                "subscribe(address,bytes32)",
                address(yieldRelayer),
                eventSig
            )
        );
        require(success, "Deploy: Reactivity subscription failed");

        console.log("[SUCCESS] Reactivity subscription created!");

        // ─────────────────────────────────────────────────
        //  6. Stop broadcast
        // ─────────────────────────────────────────────────
        vm.stopBroadcast();

        // ─────────────────────────────────────────────────
        //  7. Print final summary for .env / frontend
        // ─────────────────────────────────────────────────
        console.log("");
        console.log("========================================");
        console.log("  DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Copy these into your .env:");
        console.log("");
        console.log("  RELAYER_CONTRACT_ADDRESS=", address(yieldRelayer));
        console.log("  OPTIMIZER_CONTRACT_ADDRESS=", address(yieldOptimizer));
        console.log("  USDC_ADDRESS=", usdcAddress);
        console.log("  PAYMASTER_ADDRESS=", paymasterAddress);
        console.log("  ROUTER_ADDRESS=", routerAddress);
        console.log("");
        console.log("Frontend viemConfig.ts CONTRACTS:");
        console.log("");
        console.log("  YIELD_OPTIMIZER:", address(yieldOptimizer));
        console.log("  YIELD_RELAYER:  ", address(yieldRelayer));
        console.log("  USDC:           ", usdcAddress);
        console.log("");
        console.log("Somnia Testnet Explorer:");
        console.log(
            "  Relayer:   https://shannon-explorer.somnia.network/address/",
            address(yieldRelayer)
        );
        console.log(
            "  Optimizer: https://shannon-explorer.somnia.network/address/",
            address(yieldOptimizer)
        );
        console.log("");
        console.log("========================================");
        console.log("  DEPLOY COMMAND:");
        console.log("  forge script script/Deploy.s.sol \\");
        console.log(
            "    --rpc-url https://api.infra.testnet.somnia.network \\"
        );
        console.log("    --account <your-keystore-name> \\");
        console.log("    --sender <your-deployer-address> \\");
        console.log("    --gas-estimate-multiplier 200 \\");
        console.log("    --broadcast");
        console.log("========================================");
    }
}
