import { createPublicClient, http, defineChain } from "viem";

/**
 * Somnia Testnet chain definition.
 *
 * Per the official Somnia Reactivity reference:
 *   Chain ID:  50312
 *   RPC HTTP:  https://api.infra.testnet.somnia.network
 *   RPC WSS:   wss://api.infra.testnet.somnia.network
 *   Explorer:  https://shannon-explorer.somnia.network
 *   Faucet:    https://testnet.somnia.network
 *   Native:    STT (18 decimals)
 */
export const somniaTestnet = defineChain({
  id: 50312,
  name: "Somnia Testnet",
  nativeCurrency: {
    name: "STT",
    symbol: "STT",
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: ["https://api.infra.testnet.somnia.network"],
      webSocket: ["wss://api.infra.testnet.somnia.network"],
    },
  },
  blockExplorers: {
    default: {
      name: "Somnia Explorer",
      url: "https://shannon-explorer.somnia.network",
    },
  },
  testnet: true,
});

/**
 * Public client for read-only interactions with the Somnia Testnet.
 *
 * Usage:
 *   const result = await publicClient.readContract({ ... });
 */
export const publicClient = createPublicClient({
  chain: somniaTestnet,
  transport: http(),
});

/**
 * Placeholder contract addresses — update with deployed addresses.
 */
export const CONTRACTS = {
  YIELD_OPTIMIZER: (process.env.NEXT_PUBLIC_YIELD_OPTIMIZER_ADDRESS || "0x00") as `0x${string}`,
  YIELD_RELAYER: (process.env.NEXT_PUBLIC_YIELD_RELAYER_ADDRESS || "0x00") as `0x${string}`,
  USDC: (process.env.NEXT_PUBLIC_USDC_ADDRESS || "0x00") as `0x${string}`,
} as const;
