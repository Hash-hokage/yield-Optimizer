require('dotenv').config();
const { ethers } = require('ethers');
const cron = require('node-cron');

// Environment Variables
const KEEPER_PRIVATE_KEY = process.env.KEEPER_PRIVATE_KEY;
const RELAYER_ADDRESS = process.env.RELAYER_ADDRESS;
const FARM_ADDRESS = process.env.FARM_ADDRESS;

if (!KEEPER_PRIVATE_KEY || !RELAYER_ADDRESS || !FARM_ADDRESS) {
    console.error("Missing required environment variables in .env");
    process.exit(1);
}

// Configuration
const RPC_URL = "https://api.infra.testnet.somnia.network";
const UPDATE_THRESHOLD_BPS = 200; // 2%

// Minimal ABI for the Relayer contract
const RELAYER_ABI = [
    "function pushYieldUpdate(uint256 _newAPY, address _targetFarm) external",
    "function currentFarmYields(address) external view returns (uint256)"
];

// Initialize Provider and Wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(KEEPER_PRIVATE_KEY, provider);

// Initialize Contract
const relayerContract = new ethers.Contract(RELAYER_ADDRESS, RELAYER_ABI, wallet);

// Helper function to generate simulated off-chain APY (500 to 2000 bps)
function getSimulatedOffchainAPY() {
    return Math.floor(Math.random() * (2000 - 500 + 1)) + 500;
}

// Core Keeper Logic
async function runKeeperTask() {
    console.log(`\n[${new Date().toISOString()}] Keeper task triggered.`);

    try {
        // 1. Fetch current on-chain APY
        const onChainAPYBigInt = await relayerContract.currentFarmYields(FARM_ADDRESS);
        const onChainAPY = Number(onChainAPYBigInt);
        console.log(`On-chain APY for farm ${FARM_ADDRESS}: ${onChainAPY} bps`);

        // 2. Generate simulated off-chain APY
        const offChainAPY = getSimulatedOffchainAPY();
        console.log(`Simulated Off-chain APY: ${offChainAPY} bps`);

        // 3. Compare APYs
        const absoluteDifference = Math.abs(offChainAPY - onChainAPY);
        console.log(`Absolute Difference: ${absoluteDifference} bps (Threshold: ${UPDATE_THRESHOLD_BPS} bps)`);

        if (absoluteDifference > UPDATE_THRESHOLD_BPS) {
            console.log(`Threshold exceeded! Pushing yield update to chain...`);
            
            // 4. Execute pushYieldUpdate
            const tx = await relayerContract.pushYieldUpdate(offChainAPY, FARM_ADDRESS);
            console.log(`Transaction broadcasted. Hash: ${tx.hash}`);
            console.log(`Waiting for confirmation...`);
            
            const receipt = await tx.wait();
            console.log(`Transaction confirmed in block ${receipt.blockNumber}.`);
        } else {
            console.log(`Difference is within threshold. No update applied.`);
        }

    } catch (error) {
        console.error(`[ERROR] Keeper task failed:`, error);
    }
}

// Start the cron job to run every 5 minutes
cron.schedule("*/5 * * * *", () => {
    runKeeperTask();
});

console.log("Keeper bot started. Monitoring off-chain APY every 5 minutes...");
// Run once immediately on start
runKeeperTask();
