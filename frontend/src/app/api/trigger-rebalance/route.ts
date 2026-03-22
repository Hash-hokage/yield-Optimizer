import { NextResponse } from "next/server";
import { ethers } from "ethers";
import { yieldRelayerABI } from "@/abi/YieldRelayer";
import fs from "fs";
import path from "path";

/**
 * POST /api/trigger-rebalance
 *
 * "God Mode" endpoint — pushes a random APY spike to the on-chain
 * YieldRelayer contract.  The wallet is decrypted in-memory from an
 * encrypted JSON keystore file.  The keystore and its password never
 * reach the browser bundle.
 */
export async function POST() {
  try {
    /* ── 1. Validate environment ── */
    const password = process.env.KEYSTORE_PASSWORD;
    if (!password) {
      return NextResponse.json(
        { success: false, error: "KEYSTORE_PASSWORD is not set or is empty" },
        { status: 500 }
      );
    }

    const relayerAddress = process.env.NEXT_PUBLIC_YIELD_RELAYER_ADDRESS;
    if (!relayerAddress) {
      throw new Error("NEXT_PUBLIC_YIELD_RELAYER_ADDRESS is not set");
    }

    const targetFarmAddress = process.env.NEXT_PUBLIC_MOCK_FARM_ADDRESS;
    if (!targetFarmAddress) {
      throw new Error("NEXT_PUBLIC_MOCK_FARM_ADDRESS is not set");
    }

    /* ── 2. Read encrypted keystore from disk ── */
    const keystorePath = path.resolve(process.cwd(), "keystore.json");
    const keystoreData = fs.readFileSync(keystorePath, "utf-8");

    /* ── 3. Decrypt wallet in memory ── */
    const wallet = await ethers.Wallet.fromEncryptedJson(keystoreData, password);

    /* ── 4. Connect to Somnia Testnet ── */
    const provider = new ethers.JsonRpcProvider(
      "https://api.infra.testnet.somnia.network"
    );
    const connectedWallet = wallet.connect(provider);

    /* ── 5. Bind to YieldRelayer contract ── */
    const yieldRelayer = new ethers.Contract(
      relayerAddress,
      yieldRelayerABI,
      connectedWallet
    );

    /* ── 6. Generate random APY (1500–2500 bps → 15%–25%) ── */
    const randomAPY = Math.floor(Math.random() * (2500 - 1500 + 1)) + 1500;

    console.log(
      `[God Mode] Triggering pushYieldUpdate  APY=${randomAPY} bps  Farm=${targetFarmAddress}`
    );

    /* ── 7. Execute on-chain tx and wait for receipt ── */
    const tx = await yieldRelayer.pushYieldUpdate(randomAPY, targetFarmAddress);
    const receipt = await tx.wait();

    console.log(`[God Mode] ✓ TX confirmed: ${receipt.hash}`);

    return NextResponse.json(
      {
        success: true,
        transactionHash: receipt.hash,
        apy: randomAPY,
      },
      { status: 200 }
    );
  } catch (err: unknown) {
    const error = err as { shortMessage?: string; message?: string };
    console.error("[God Mode] Error triggering rebalance:", err);

    return NextResponse.json(
      {
        success: false,
        error: error.shortMessage || error.message || "Failed to trigger rebalance",
      },
      { status: 500 }
    );
  }
}
