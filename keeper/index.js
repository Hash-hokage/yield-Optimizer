/**
 * ============================================================
 *  Somnia Yield Keeper — Off-Chain APY Relayer Service
 * ============================================================
 *
 * This Node.js process is the autonomous backend brain for the
 * Somnia Testnet Yield Optimizer.  It runs two concurrent engines:
 *
 *   Engine 1 — Health Server  (Express)
 *     A lightweight HTTP server that cloud providers (Render,
 *     Railway, etc.) ping to confirm the process is alive.
 *
 *   Engine 2 — Blockchain Loop  (setInterval)
 *     A polling loop that runs every 60 seconds, simulates
 *     fetching a live APY, and — when the deviation exceeds
 *     a threshold — pushes the new figure on-chain via the
 *     YieldRelayer smart contract.
 *
 * Environment Variables (via .env):
 *   KEEPER_PRIVATE_KEY        — Private key of the Keeper EOA
 *   RELAYER_CONTRACT_ADDRESS  — Deployed YieldRelayer address
 *   TARGET_FARM_ADDRESS       — Address of the target farm/vault
 *   SOMNIA_RPC_URL            — Somnia Testnet JSON-RPC endpoint
 *   PORT                      — (optional) HTTP port, default 3000
 * ============================================================
 */

require("dotenv").config();
const express = require("express");
const { ethers } = require("ethers");

// ─── Configuration ──────────────────────────────────────────
const PORT = process.env.PORT || 3000;
const POLL_INTERVAL_MS = 60_000; // 1 minute
const DEVIATION_THRESHOLD_BPS = 200; // 2 % in basis points
const APY_MIN_BPS = 300; // floor for simulated APY
const APY_MAX_BPS = 800; // ceiling for simulated APY

// ─── YieldRelayer ABI (only the function we call) ───────────
const RELAYER_ABI = [
  "function pushYieldUpdate(uint256 _newAPY, address _targetFarm) external",
];

// ════════════════════════════════════════════════════════════
//  ENGINE 1 — Health Server
// ════════════════════════════════════════════════════════════

const app = express();

app.get("/", (_req, res) => {
  res.status(200).json({
    status: "ok",
    service: "somnia-yield-keeper",
    uptime: process.uptime(),
  });
});

app.listen(PORT, () => {
  console.log(`[Health] Server listening on port ${PORT}`);
});

// ════════════════════════════════════════════════════════════
//  ENGINE 2 — Blockchain Polling Loop
// ════════════════════════════════════════════════════════════

/**
 * Tracks the last APY value that was successfully pushed on-chain.
 * Compared against each new reading to decide whether a transaction
 * is warranted.
 */
let lastPushedAPY = 0;

/**
 * Simulates fetching a live APY from an off-chain data source.
 * In production this would query a DeFi aggregator API.
 *
 * @returns {number} A random APY in basis points (300 – 800).
 */
function fetchSimulatedAPY() {
  return Math.floor(Math.random() * (APY_MAX_BPS - APY_MIN_BPS + 1)) + APY_MIN_BPS;
}

/**
 * Core keeper loop iteration.
 *
 * 1. Simulates an off-chain APY fetch.
 * 2. Checks whether the new value deviates from the last pushed
 *    value by more than DEVIATION_THRESHOLD_BPS.
 * 3. If it does, sends a `pushYieldUpdate` transaction to the
 *    YieldRelayer contract and waits for confirmation.
 *
 * The entire body is wrapped in try/catch so that transient RPC
 * timeouts or nonce errors do not crash the Node process.
 */
async function keeperTick() {
  try {
    const newAPY = fetchSimulatedAPY();
    const deviation = Math.abs(newAPY - lastPushedAPY);

    console.log(
      `[Keeper] Fetched APY: ${newAPY} bps | Last pushed: ${lastPushedAPY} bps | Deviation: ${deviation} bps`
    );

    if (deviation <= DEVIATION_THRESHOLD_BPS) {
      console.log("[Keeper] Deviation below threshold — skipping transaction.");
      return;
    }

    // ── Build signer & contract instance ──────────────────
    const provider = new ethers.JsonRpcProvider(process.env.SOMNIA_RPC_URL);
    const wallet = new ethers.Wallet(process.env.KEEPER_PRIVATE_KEY, provider);
    const relayer = new ethers.Contract(
      process.env.RELAYER_CONTRACT_ADDRESS,
      RELAYER_ABI,
      wallet
    );

    const targetFarm = process.env.TARGET_FARM_ADDRESS;

    console.log(
      `[Keeper] Pushing APY update — newAPY: ${newAPY} bps → farm: ${targetFarm}`
    );

    // ── Send the transaction ──────────────────────────────
    const tx = await relayer.pushYieldUpdate(newAPY, targetFarm);
    console.log(`[Keeper] Tx sent — hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log(
      `[Keeper] Tx confirmed in block ${receipt.blockNumber} ✔`
    );

    // Update local state only after on-chain confirmation
    lastPushedAPY = newAPY;
  } catch (error) {
    console.error("[Keeper] Error during tick — will retry next interval:");
    console.error(error.message || error);
  }
}

// ── Kick off the loop (runs concurrently with Express) ────
console.log(
  `[Keeper] Starting polling loop — interval: ${POLL_INTERVAL_MS / 1000}s, threshold: ${DEVIATION_THRESHOLD_BPS} bps`
);

// Run once immediately on startup, then every POLL_INTERVAL_MS
keeperTick();
setInterval(keeperTick, POLL_INTERVAL_MS);
