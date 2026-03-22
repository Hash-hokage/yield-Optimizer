"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Rocket, CheckCircle, XCircle, ExternalLink } from "lucide-react";

export function DemoButton() {
  const [isLoading, setIsLoading] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [apyBps, setApyBps] = useState<number | null>(null);

  const simulateApySpike = async () => {
    setIsLoading(true);
    setTxHash(null);
    setError(null);
    setApyBps(null);

    try {
      const response = await fetch("/api/trigger-rebalance", {
        method: "POST",
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || "Failed to trigger rebalance");
      }

      setTxHash(data.transactionHash);
      setApyBps(data.apy);
    } catch (err: unknown) {
      const error = err as { message?: string };
      console.error("[DemoButton]", err);
      setError(error.message || "An unexpected error occurred");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: "easeOut" }}
      className="relative w-full max-w-sm"
    >
      {/* Glow backdrop */}
      <div className="absolute -inset-px rounded-2xl bg-gradient-to-b from-indigo-500/20 via-violet-500/10 to-transparent blur-xl opacity-60" />

      <div className="relative flex flex-col items-center gap-4 p-6 rounded-2xl bg-zinc-900/80 backdrop-blur-xl border border-zinc-800/60 ring-1 ring-white/[0.03]">
        {/* Header */}
        <div className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-indigo-500/10 ring-1 ring-indigo-500/20">
            <Rocket className="h-4 w-4 text-indigo-400" />
          </div>
          <h3 className="text-base font-semibold text-zinc-100 tracking-tight">
            God Mode
          </h3>
        </div>

        <p className="text-xs text-zinc-500 text-center leading-relaxed">
          Manually push a random APY spike to the on-chain YieldRelayer —
          triggering Somnia&apos;s reactive rebalance pipeline.
        </p>

        {/* CTA Button */}
        <motion.button
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={simulateApySpike}
          disabled={isLoading}
          className={`
            relative flex items-center justify-center w-full gap-2.5 px-6 py-3.5
            font-semibold text-sm text-white rounded-xl transition-all duration-200
            focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500/50
            ${
              isLoading
                ? "bg-indigo-500/30 cursor-not-allowed"
                : "bg-gradient-to-r from-indigo-600 to-violet-600 hover:from-indigo-500 hover:to-violet-500 shadow-lg shadow-indigo-500/25"
            }
          `}
        >
          {isLoading ? (
            <>
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />
              Triggering Reactivity…
            </>
          ) : (
            <>
              <Rocket className="h-4 w-4" />
              Simulate APY Spike
            </>
          )}
        </motion.button>

        {/* Status Toast Area */}
        <AnimatePresence mode="wait">
          {error && (
            <motion.div
              key="error"
              initial={{ opacity: 0, y: -8, height: 0 }}
              animate={{ opacity: 1, y: 0, height: "auto" }}
              exit={{ opacity: 0, y: -8, height: 0 }}
              className="w-full overflow-hidden"
            >
              <div className="flex items-start gap-2.5 p-3 text-sm text-red-300 bg-red-500/8 border border-red-500/20 rounded-xl">
                <XCircle className="h-4 w-4 text-red-400 mt-0.5 shrink-0" />
                <span className="break-all text-xs leading-relaxed">
                  {error}
                </span>
              </div>
            </motion.div>
          )}

          {txHash && (
            <motion.div
              key="success"
              initial={{ opacity: 0, y: -8, height: 0 }}
              animate={{ opacity: 1, y: 0, height: "auto" }}
              exit={{ opacity: 0, y: -8, height: 0 }}
              className="w-full overflow-hidden"
            >
              <div className="flex flex-col gap-2 p-3 bg-emerald-500/8 border border-emerald-500/20 rounded-xl">
                <div className="flex items-center gap-2">
                  <CheckCircle className="h-4 w-4 text-emerald-400 shrink-0" />
                  <span className="text-sm font-medium text-emerald-300">
                    Reactivity Triggered!
                  </span>
                  {apyBps && (
                    <span className="ml-auto text-xs font-mono text-emerald-400/80">
                      {(apyBps / 100).toFixed(2)}% APY
                    </span>
                  )}
                </div>
                <a
                  href={`https://somnia-testnet.socialscan.io/tx/${txHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-1.5 text-xs text-emerald-400 hover:text-emerald-300 transition-colors break-all font-mono"
                >
                  <ExternalLink className="h-3 w-3 shrink-0" />
                  {txHash.slice(0, 10)}…{txHash.slice(-8)}
                </a>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  );
}
