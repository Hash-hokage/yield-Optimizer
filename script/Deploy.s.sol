// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {YieldRelayer} from "../src/YieldRelayer.sol";
import {YieldOptimizer} from "../src/YieldOptimizer.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockUniswapV2Factory} from "../src/mocks/MockUniswapV2Factory.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";

/// @title Deploy
/// @author Hash-Hokage
/// @notice Foundry deployment script for the Somnia Yield Optimizer architecture.
/// @dev Deploys an isolated ecosystem (Mock Tokens, Mock Factory, Mock DEX, Liquidity),
///      then deploys `YieldRelayer` and `YieldOptimizer`. Finally, it creates a reactivity
///      subscription on the Somnia Precompile at `0x0100` so that `YieldUpdated`
///      events emitted by the Relayer are automatically routed to the Optimizer's
///      `onYieldUpdated` callback.
///
///      **Authentication:**
///      Uses Foundry's encrypted keystore (`--account`). NEVER store
///      private keys in plaintext, .env files, or source code.
///
///      **Environment Variables Required (addresses only):**
///      - `PAYMASTER_ADDRESS` — Address of the paymaster for gas reimbursement
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
contract Deploy is Script {
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

    function run()
        external
        returns (
            address deployedUsdc,
            address deployedTargetToken,
            address deployedMockDex,
            address deployedYieldRelayer,
            address deployedYieldOptimizer
        )
    {
        // ─────────────────────────────────────────────────
        //  1. Load environment variables (addresses only)
        // ─────────────────────────────────────────────────
        address paymasterAddress = vm.envAddress("PAYMASTER_ADDRESS");

        console.log("========================================");
        console.log("  SOMNIA YIELD OPTIMIZER -- DEPLOYMENT");
        console.log("========================================");
        console.log("");
        console.log("Paymaster:           ", paymasterAddress);
        console.log("Max Loss Threshold:  ", MAX_LOSS_THRESHOLD);
        console.log("");

        // ─────────────────────────────────────────────────
        //  2. Start broadcast
        // ─────────────────────────────────────────────────
        vm.startBroadcast();

        address deployer = msg.sender;
        console.log("Deployer:            ", deployer);
        console.log("Deployer balance:    ", deployer.balance);

        require(
            deployer.balance >= SUBSCRIPTION_DEPOSIT, "Deploy: Deployer must hold >= 32 STT for subscription deposit"
        );

        // ─────────────────────────────────────────────────
        //  3. The Sandbox Phase (Mock Ecosystem)
        // ─────────────────────────────────────────────────
        console.log("");
        console.log("--- Sandbox Ecosystem Deployment ---");

        // Deploy Tokens
        MockERC20 usdc = new MockERC20("Mock USDC", "USDC", 6);
        MockERC20 targetToken = new MockERC20("Target Farm Token", "TGT", 18);
        console.log("[DEPLOYED] Mock USDC:         ", address(usdc));
        console.log("[DEPLOYED] TargetToken (TGT): ", address(targetToken));

        // Mint 1,000,000 of each to deployer
        usdc.mint(deployer, 1_000_000e6);
        targetToken.mint(deployer, 1_000_000e18);

        // Deploy AMM
        MockUniswapV2Factory mockFactory = new MockUniswapV2Factory();
        console.log("[DEPLOYED] Mock Factory:      ", address(mockFactory));

        MockDEX mockDex = new MockDEX();
        mockDex.setFactory(address(mockFactory));
        console.log("[DEPLOYED] Mock DEX Router:   ", address(mockDex));

        // Seed Liquidity
        // Approve the MockDEX router (even though mockDex doesn't strictly pull for `setReserves`,
        // it's good practice and fulfills the requirement)
        usdc.approve(address(mockDex), type(uint256).max);
        targetToken.approve(address(mockDex), type(uint256).max);

        // Establish the 1:1 price ratio and 100k deep liquidity
        mockDex.setReserves(address(usdc), address(targetToken), 100_000e6, 100_000e18);

        // Also register the pair in the factory (helpful if optimizer checks it)
        mockFactory.setPair(address(usdc), address(targetToken), address(mockDex)); // Pair address doesn't matter for the mock, just needs to not be zero

        console.log("[SEEDED]   Liquidity for USDC/TGT set on Mock DEX");

        // ─────────────────────────────────────────────────
        //  4. The Core Deployment Phase
        // ─────────────────────────────────────────────────
        console.log("");
        console.log("--- Core Optimizer Architecture ---");

        YieldRelayer yieldRelayer = new YieldRelayer(deployer);
        console.log("[DEPLOYED] YieldRelayer:      ", address(yieldRelayer));

        YieldOptimizer yieldOptimizer = new YieldOptimizer(
            address(usdc),
            paymasterAddress,
            address(yieldRelayer), // trustedOracle
            address(mockDex), // router
            MAX_LOSS_THRESHOLD
        );
        console.log("[DEPLOYED] YieldOptimizer:    ", address(yieldOptimizer));

        // ─────────────────────────────────────────────────
        //  5. Somnia Reactivity Integration
        // ─────────────────────────────────────────────────
        bytes32 eventSig = keccak256("YieldUpdated(uint256,address)");

        console.log("");
        console.log("--- Reactivity Subscription ---");
        console.log("Precompile:          ", REACTIVITY_PRECOMPILE);
        console.log("Emitter:             ", address(yieldRelayer));
        console.log("Event signature:     ");
        console.logBytes32(eventSig);

        (bool success,) = REACTIVITY_PRECOMPILE.call{value: SUBSCRIPTION_DEPOSIT}(
            abi.encodeWithSignature("subscribe(address,bytes32)", address(yieldRelayer), eventSig)
        );
        require(success, "Deploy: Reactivity subscription failed");

        console.log("[SUCCESS] Reactivity subscription created!");

        // ─────────────────────────────────────────────────
        //  6. Stop broadcast
        // ─────────────────────────────────────────────────
        vm.stopBroadcast();

        // ─────────────────────────────────────────────────
        //  7. Output Logs for the Frontend .env
        // ─────────────────────────────────────────────────
        console.log("");
        console.log("========================================");
        console.log("  DEPLOYMENT COMPLETE (ISOLATED SANDBOX)");
        console.log("========================================");
        console.log("");
        console.log("Copy these into your .env/viemConfig.ts:");
        console.log("");
        console.log("  USDC_ADDRESS=", address(usdc));
        console.log("  TARGET_TOKEN_ADDRESS=", address(targetToken));
        console.log("  ROUTER_ADDRESS=", address(mockDex));
        console.log("  FACTORY_ADDRESS=", address(mockFactory));
        console.log("  YIELD_RELAYER_ADDRESS=", address(yieldRelayer));
        console.log("  YIELD_OPTIMIZER_ADDRESS=", address(yieldOptimizer));
        console.log("");
        console.log("========================================");

        // ─────────────────────────────────────────────────
        //  8. Return deployed addresses for testing
        // ─────────────────────────────────────────────────
        return (address(usdc), address(targetToken), address(mockDex), address(yieldRelayer), address(yieldOptimizer));
    }
}
