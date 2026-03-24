"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Rocket, CheckCircle, XCircle, ExternalLink, Zap, Loader2 } from "lucide-react";
import { useYieldOptimizer } from "@/hooks/useYieldOptimizer";
import { formatUnits } from "viem";

export function DemoButton({ lastExecution }: {
  lastExecution: ReturnType<typeof useYieldOptimizer>['lastExecution']
}) {
  const [isLoading, setIsLoading] = useState(false);
  const [relayerTxHash, setRelayerTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [apyBps, setApyBps] = useState<number | null>(null);
  const [waitingForReactive, setWaitingForReactive] = useState(false);
  const [reactiveTimedOut, setReactiveTimedOut] = useState(false);


  // When lastExecution updates after we triggered a rebalance, clear the waiting state
  const [triggerTime, setTriggerTime] = useState<number | null>(null);
  const reactiveConfirmed =
    triggerTime !== null &&
    lastExecution !== null &&
    lastExecution.timestamp > triggerTime;

  const simulateApySpike = async () => {
    setIsLoading(true);
    setRelayerTxHash(null);
    setError(null);
    setApyBps(null);
    setWaitingForReactive(false);
    setReactiveTimedOut(false);

    try {
      const response = await fetch("/api/trigger-rebalance", { method: "POST" });
      const data = await response.json();

      if (!response.ok) throw new Error(data.error || "Failed to trigger rebalance");

      setRelayerTxHash(data.transactionHash);
      setApyBps(data.apy);
      setTriggerTime(Date.now());
      setWaitingForReactive(true);
      // Time out after 30 seconds if reactive callback hasn't fired
      setTimeout(() => {
        setReactiveTimedOut(true);
        setWaitingForReactive(false);
      }, 30_000);
    } catch (err: unknown) {
      const e = err as { message?: string };
      setError(e.message || "An unexpected error occurred");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: "easeOut" }}
      className="relative w-full max-w-md"
    >
      {/* Glow backdrop */}
      <div className="absolute -inset-px rounded-2xl bg-gradient-to-b from-indigo-500/20 via-violet-500/10 to-transparent blur-xl opacity-60" />

      <div className="relative flex flex-col items-center gap-5 p-6 rounded-2xl bg-zinc-900/80 backdrop-blur-xl border border-zinc-800/60 ring-1 ring-white/[0.03]">

        {/* Header */}
        <div className="flex items-center gap-2.5 self-start">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-indigo-500/10 ring-1 ring-indigo-500/20">
            <Rocket className="h-4 w-4 text-indigo-400" />
          </div>
          <div>
            <h3 className="text-sm font-semibold text-zinc-100 tracking-tight">God Mode</h3>
            <p className="text-xs text-zinc-500">Trigger the reactive pipeline</p>
          </div>
        </div>

        {/* Two-step flow visual */}
        <div className="w-full grid grid-cols-2 gap-2">
          {/* Step 1 */}
          <div className={`rounded-xl p-3 border transition-colors duration-500 ${relayerTxHash
              ? "border-emerald-500/30 bg-emerald-500/5"
              : "border-zinc-800/60 bg-zinc-800/20"
            }`}>
            <div className="flex items-center gap-2 mb-1">
              {relayerTxHash
                ? <CheckCircle className="h-3.5 w-3.5 text-emerald-400 shrink-0" />
                : <div className="h-3.5 w-3.5 rounded-full border border-zinc-700 shrink-0" />
              }
              <span className="text-xs font-medium text-zinc-300">Step 1</span>
            </div>
            <p className="text-[11px] text-zinc-500 leading-relaxed">
              Push APY update to <span className="text-blue-400 font-mono">YieldRelayer</span>
            </p>
          </div>

          {/* Step 2 */}
          <div className={`rounded-xl p-3 border transition-colors duration-500 ${reactiveConfirmed
              ? "border-violet-500/30 bg-violet-500/5"
              : waitingForReactive
                ? "border-zinc-700/60 bg-zinc-800/20 animate-pulse"
                : "border-zinc-800/60 bg-zinc-800/20"
            }`}>
            <div className="flex items-center gap-2 mb-1">
              {reactiveConfirmed
                ? <Zap className="h-3.5 w-3.5 text-violet-400 shrink-0" />
                : waitingForReactive
                  ? <Loader2 className="h-3.5 w-3.5 text-zinc-500 shrink-0 animate-spin" />
                  : <div className="h-3.5 w-3.5 rounded-full border border-zinc-700 shrink-0" />
              }
              <span className="text-xs font-medium text-zinc-300">Step 2</span>
            </div>
            <p className="text-[11px] text-zinc-500 leading-relaxed">
              Somnia precompile triggers <span className="text-violet-400 font-mono">YieldOptimizer</span>
            </p>
          </div>
        </div>

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
            ${isLoading
              ? "bg-indigo-500/30 cursor-not-allowed"
              : "bg-gradient-to-r from-indigo-600 to-violet-600 hover:from-indigo-500 hover:to-violet-500 shadow-lg shadow-indigo-500/25"
            }
          `}
        >
          {isLoading ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" />
              Triggering Reactivity…
            </>
          ) : (
            <>
              <Rocket className="h-4 w-4" />
              Simulate APY Spike
            </>
          )}
        </motion.button>

        {/* Status Area */}
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
                <span className="break-all text-xs leading-relaxed">{error}</span>
              </div>
            </motion.div>
          )}

          {relayerTxHash && !reactiveConfirmed && (
            <motion.div
              key="relayer-confirmed"
              initial={{ opacity: 0, y: -8, height: 0 }}
              animate={{ opacity: 1, y: 0, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              className="w-full overflow-hidden"
            >
              <div className="flex flex-col gap-2 p-3 bg-emerald-500/8 border border-emerald-500/20 rounded-xl">
                <div className="flex items-center gap-2">
                  <CheckCircle className="h-4 w-4 text-emerald-400 shrink-0" />
                  <span className="text-xs font-medium text-emerald-300">
                    APY spike pushed on-chain
                    {apyBps && (
                      <span className="ml-2 font-mono text-emerald-400/80">
                        {(apyBps / 100).toFixed(2)}%
                      </span>
                    )}
                  </span>
                </div>
                <a
                  href={`https://shannon-explorer.somnia.network/tx/${relayerTxHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-1.5 text-xs text-emerald-400 hover:text-emerald-300 transition-colors font-mono"
                >
                  <ExternalLink className="h-3 w-3 shrink-0" />
                  {relayerTxHash.slice(0, 10)}…{relayerTxHash.slice(-8)}
                </a>
                {reactiveTimedOut ? (
                  <p className="text-[11px] text-amber-500 flex items-center gap-1.5">
                    ⚠ Reactive callback not detected — check explorer for on-chain activity
                  </p>
                ) : (
                  <p className="text-[11px] text-zinc-500 flex items-center gap-1.5">
                    <Loader2 className="h-3 w-3 animate-spin shrink-0" />
                    Waiting for Somnia reactive callback…
                  </p>
                )}
              </div>
            </motion.div>
          )}

          {reactiveConfirmed && lastExecution && (
            <motion.div
              key="reactive-confirmed"
              initial={{ opacity: 0, scale: 0.97, y: -8 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              transition={{ type: "spring", duration: 0.5 }}
              className="w-full"
            >
              <div className="flex flex-col gap-2.5 p-3.5 bg-violet-500/8 border border-violet-500/25 rounded-xl">
                <div className="flex items-center gap-2">
                  <Zap className="h-4 w-4 text-violet-400 shrink-0" />
                  <span className="text-xs font-semibold text-violet-300">
                    Reactive rebalance confirmed!
                  </span>
                </div>
                <div className="grid grid-cols-2 gap-2 text-[11px]">
                  <div className="space-y-0.5">
                    <p className="text-zinc-500">Target Farm</p>
                    <p className="font-mono text-zinc-300">
                      {lastExecution.targetFarm.slice(0, 6)}…{lastExecution.targetFarm.slice(-4)}
                    </p>
                  </div>
                  <div className="space-y-0.5">
                    <p className="text-zinc-500">Net Profit</p>
                    <p className="font-mono text-emerald-400">
                      ${formatUnits(lastExecution.profitUSDC, 6)} USDC
                    </p>
                  </div>
                  <div className="space-y-0.5">
                    <p className="text-zinc-500">Gas Used</p>
                    <p className="font-mono text-zinc-300">
                      {Number(lastExecution.gasSpent).toLocaleString()}
                    </p>
                  </div>
                  <div className="space-y-0.5">
                    <p className="text-zinc-500">Triggered by</p>
                    <p className="font-mono text-violet-400">0x0100 precompile</p>
                  </div>
                </div>
                {lastExecution.txHash && (
                  <a
                    href={`https://shannon-explorer.somnia.network/tx/${lastExecution.txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-1.5 text-xs text-violet-400 hover:text-violet-300 transition-colors font-mono"
                  >
                    <ExternalLink className="h-3 w-3 shrink-0" />
                    View reactive tx →
                  </a>
                )}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  );
}
