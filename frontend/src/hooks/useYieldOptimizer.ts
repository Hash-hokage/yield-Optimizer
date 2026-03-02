"use client";

import { useState, useEffect } from "react";
// import { publicClient, CONTRACTS } from "@/lib/viemConfig";

/**
 * ABI fragments for YieldOptimizer read functions.
 * Uncomment and use when contract is deployed.
 */
// const YIELD_OPTIMIZER_ABI = [
//   { name: "currentFarm", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
//   { name: "isPaused", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
//   { name: "cumulativeLoss", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
//   { name: "maxLossThreshold", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
//   { name: "trustedOracle", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
//   { name: "cachedReserveUSDC", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
//   { name: "cachedReserveTarget", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
//   { name: "owner", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
// ] as const;

export interface YieldOptimizerState {
  currentFarm: string;
  currentAPY: string;
  totalValueOptimized: string;
  cumulativeLoss: string;
  maxLossThreshold: string;
  isPaused: boolean;
  trustedOracle: string;
  cachedReserveUSDC: string;
  isLoading: boolean;
}

/**
 * Hook to read on-chain state from the YieldOptimizer contract.
 *
 * Currently returns mock/skeleton data. Once the contract is deployed on Somnia
 * Testnet, uncomment the `publicClient.readContract(...)` calls below and
 * replace the mock data with real reads.
 */
export function useYieldOptimizer(): YieldOptimizerState {
  const [state, setState] = useState<YieldOptimizerState>({
    currentFarm: "",
    currentAPY: "0",
    totalValueOptimized: "0",
    cumulativeLoss: "0",
    maxLossThreshold: "0",
    isPaused: false,
    trustedOracle: "",
    cachedReserveUSDC: "0",
    isLoading: true,
  });

  useEffect(() => {
    const fetchContractState = async () => {
      try {
        // ──────────────────────────────────────────────
        // TODO: Replace with real contract reads once deployed
        // ──────────────────────────────────────────────
        //
        // const [currentFarm, isPaused, cumulativeLoss, maxLossThreshold, trustedOracle, cachedReserveUSDC] =
        //   await Promise.all([
        //     publicClient.readContract({ address: CONTRACTS.YIELD_OPTIMIZER, abi: YIELD_OPTIMIZER_ABI, functionName: "currentFarm" }),
        //     publicClient.readContract({ address: CONTRACTS.YIELD_OPTIMIZER, abi: YIELD_OPTIMIZER_ABI, functionName: "isPaused" }),
        //     publicClient.readContract({ address: CONTRACTS.YIELD_OPTIMIZER, abi: YIELD_OPTIMIZER_ABI, functionName: "cumulativeLoss" }),
        //     publicClient.readContract({ address: CONTRACTS.YIELD_OPTIMIZER, abi: YIELD_OPTIMIZER_ABI, functionName: "maxLossThreshold" }),
        //     publicClient.readContract({ address: CONTRACTS.YIELD_OPTIMIZER, abi: YIELD_OPTIMIZER_ABI, functionName: "trustedOracle" }),
        //     publicClient.readContract({ address: CONTRACTS.YIELD_OPTIMIZER, abi: YIELD_OPTIMIZER_ABI, functionName: "cachedReserveUSDC" }),
        //   ]);

        // Simulate network delay for skeleton loader demonstration
        await new Promise((resolve) => setTimeout(resolve, 2000));

        setState({
          currentFarm: "0x1a2b...3c4d",
          currentAPY: "12.45",
          totalValueOptimized: "1,248,320",
          cumulativeLoss: "142",
          maxLossThreshold: "10,000",
          isPaused: false,
          trustedOracle: "0x5e6f...7a8b",
          cachedReserveUSDC: "500,000",
          isLoading: false,
        });
      } catch (error) {
        console.error("Failed to fetch contract state:", error);
        setState((prev) => ({ ...prev, isLoading: false }));
      }
    };

    fetchContractState();
  }, []);

  return state;
}
