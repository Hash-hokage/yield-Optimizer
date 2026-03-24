"use client";

import type { useYieldOptimizer } from "@/hooks/useYieldOptimizer";
import { useState } from "react";
import { motion } from "framer-motion";
import {
  Activity,
  TrendingUp,
  DollarSign,
  ShieldCheck,
  Sparkles,
  ArrowRight,
} from "lucide-react";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { parseUnits, formatUnits } from "viem";

/* ─────────────────────────────────────────
   Animation variants
   ───────────────────────────────────────── */
const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { staggerChildren: 0.08, delayChildren: 0.1 },
  },
};

const itemVariants = {
  hidden: { opacity: 0, y: 16 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.45, ease: "easeOut" as const } },
};

const cardHover = {
  rest: { scale: 1 },
  hover: { scale: 1.005, transition: { duration: 0.25 } },
};

/* ─────────────────────────────────────────
   Skeleton placeholder
   ───────────────────────────────────────── */
function Skeleton({ className = "" }: { className?: string }) {
  return (
    <div
      className={`relative overflow-hidden rounded-lg bg-zinc-800/60 ${className}`}
    >
      <div className="absolute inset-0 -translate-x-full animate-shimmer bg-gradient-to-r from-transparent via-zinc-700/30 to-transparent" />
    </div>
  );
}

/* ─────────────────────────────────────────
   Stat row component
   ───────────────────────────────────────── */
function StatRow({
  icon: Icon,
  label,
  value,
  suffix,
  isLoading,
  accent,
}: {
  icon: React.ElementType;
  label: string;
  value: string;
  suffix?: string;
  isLoading: boolean;
  accent?: string;
}) {
  return (
    <motion.div
      variants={itemVariants}
      className="flex items-center justify-between py-3.5 border-b border-zinc-800/40 last:border-b-0"
    >
      <div className="flex items-center gap-3">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-zinc-800/60 ring-1 ring-zinc-700/40">
          <Icon className={`h-4 w-4 ${accent || "text-zinc-400"}`} />
        </div>
        <span className="text-sm text-zinc-400">{label}</span>
      </div>
      {isLoading ? (
        <Skeleton className="h-5 w-24" />
      ) : (
        <span className="text-sm font-semibold text-zinc-100 font-mono tabular-nums">
          {value}
          {suffix && (
            <span className="ml-1 text-xs text-zinc-500 font-sans">
              {suffix}
            </span>
          )}
        </span>
      )}
    </motion.div>
  );
}

/* ─────────────────────────────────────────
   Helper
   ───────────────────────────────────────── */
function shortenAddress(addr: string): string {
  if (!addr || addr === '0x0000000000000000000000000000000000000000') return 'None'
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`
}

// Map known farm addresses to human-readable names.
// Add entries here when new farms are whitelisted.
const FARM_NAMES: Record<string, string> = {
  ...(process.env.NEXT_PUBLIC_MOCK_FARM_ADDRESS
    ? { [process.env.NEXT_PUBLIC_MOCK_FARM_ADDRESS.toLowerCase()]: 'MockYieldFarm (TGT)' }
    : {}),
}

function getFarmLabel(addr: string): string {
  if (!addr || addr === '0x0000000000000000000000000000000000000000') return 'None'
  const name = FARM_NAMES[addr.toLowerCase()]
  return name ? `${name}` : shortenAddress(addr)
}

function getFarmSublabel(addr: string): string | null {
  if (!addr || addr === '0x0000000000000000000000000000000000000000') return null
  const name = FARM_NAMES[addr.toLowerCase()]
  return name ? shortenAddress(addr) : null
}

/* ═════════════════════════════════════════
   Main Dashboard Component
   ═════════════════════════════════════════ */
export default function YieldDashboard({ data }: { data: ReturnType<typeof useYieldOptimizer> }) {
  const { cumulativeLoss, maxLossThreshold, isPaused, tvl, currentFarm, currentAPYBps, ...optimizer } = data;
  const isLoggedIn = !!optimizer.address;

  const [amount, setAmount] = useState("");

  // Real-time parsed formatted values
  const displayUsdc = optimizer.usdcBalance ? formatUnits(optimizer.usdcBalance as bigint, 6) : "0";
  const displayShares = optimizer.userShares ? formatUnits(optimizer.userShares as bigint, 6) : "0";

  const displayAPY = currentAPYBps
    ? `${(Number(currentAPYBps as bigint) / 100).toFixed(2)}%`
    : '—'

  // Deposit Math
  const depositValueBigInt = amount ? parseUnits(amount, 6) : BigInt(0);
  const currentAllowance = (optimizer.usdcAllowance as bigint) || BigInt(0);
  const needsApproval = depositValueBigInt > currentAllowance;

  const handleOptimize = async () => {
    if (!depositValueBigInt || !isLoggedIn) return;

    if (needsApproval) {
      await optimizer.handleApproveUSDC(depositValueBigInt);
    } else {
      await optimizer.handleDeposit(depositValueBigInt);
      setAmount(""); // clear on success
    }
  };

  const handleWithdrawAll = async () => {
    if (!optimizer.userShares || (optimizer.userShares as bigint) === BigInt(0)) return;
    await optimizer.handleWithdraw(optimizer.userShares as bigint);
  };

  return (
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      className="grid grid-cols-1 lg:grid-cols-2 gap-6"
    >
      {/* ═══════════════════════════════════
          LEFT COLUMN — Aave-style Dashboard
          ═══════════════════════════════════ */}
      <motion.div variants={itemVariants} className="space-y-5">
        {/* Portfolio Overview Card */}
        <motion.div variants={cardHover} initial="rest" whileHover="hover">
          <Card className="overflow-hidden">
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="text-base">
                    Portfolio Overview
                  </CardTitle>
                  <CardDescription className="mt-1">
                    Real-time optimizer metrics
                  </CardDescription>
                </div>
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-500/8 ring-1 ring-emerald-500/15">
                  <Activity className="h-5 w-5 text-emerald-400" />
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <motion.div
                variants={containerVariants}
                initial="hidden"
                animate="visible"
              >
                {/* Active Farm row — custom to support address sublabel */}
                <motion.div
                  variants={itemVariants}
                  className="flex items-center justify-between py-3.5 border-b border-zinc-800/40"
                >
                  <div className="flex items-center gap-3">
                    <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-zinc-800/60 ring-1 ring-zinc-700/40">
                      <Activity className={`h-4 w-4 text-cyan-400`} />
                    </div>
                    <span className="text-sm text-zinc-400">Active Farm</span>
                  </div>
                  {currentFarm === undefined ? (
                    <Skeleton className="h-5 w-24" />
                  ) : (
                    <div className="text-right">
                      <span className="text-sm font-semibold text-zinc-100 font-mono">
                        {getFarmLabel(currentFarm as string)}
                      </span>
                      {getFarmSublabel(currentFarm as string) && (
                        <p className="text-[11px] text-zinc-600 font-mono mt-0.5">
                          {getFarmSublabel(currentFarm as string)}
                        </p>
                      )}
                    </div>
                  )}
                </motion.div>
                <StatRow
                  icon={TrendingUp}
                  label="Current Farm APY"
                  value={displayAPY}
                  isLoading={currentAPYBps === undefined}
                  accent="text-yellow-400"
                />
                <StatRow
                  icon={TrendingUp}
                  label="Your Vault Shares"
                  value={Number(displayShares).toLocaleString(undefined, { maximumFractionDigits: 4 })}
                  suffix="yOpt"
                  isLoading={false}
                  accent="text-emerald-400"
                />
                <StatRow
                  icon={DollarSign}
                  label="Total Value Optimized"
                  value={`$${Number(formatUnits((tvl as bigint) ?? BigInt(0), 6)).toLocaleString(undefined, { maximumFractionDigits: 2 })}`}
                  isLoading={tvl === undefined}
                  accent="text-violet-400"
                />
              </motion.div>
            </CardContent>
          </Card>
        </motion.div>

        {/* RiskGuard Status Card */}
        <motion.div variants={cardHover} initial="rest" whileHover="hover">
          <Card>
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <CardTitle className="text-base">RiskGuard</CardTitle>
                <motion.div
                  initial={{ scale: 0.8, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={{ delay: 0.3 }}
                >
                  <span className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold ring-1 ${isPaused
                    ? 'bg-red-500/10 text-red-400 ring-red-500/20'
                    : 'bg-emerald-500/10 text-emerald-400 ring-emerald-500/20'
                    }`}>
                    <ShieldCheck className="h-3 w-3" />
                    {isPaused ? 'Paused' : 'Active'}
                  </span>
                </motion.div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-zinc-500">Cumulative Loss</span>
                  <span className="text-zinc-300 font-mono tabular-nums">
                    ${Number(formatUnits((cumulativeLoss as bigint) ?? BigInt(0), 6)).toLocaleString(undefined, { maximumFractionDigits: 2 })}
                  </span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-zinc-500">Max Threshold</span>
                  <span className="text-zinc-300 font-mono tabular-nums">
                    ${Number(formatUnits((maxLossThreshold as bigint) ?? BigInt(0), 6)).toLocaleString(undefined, { maximumFractionDigits: 2 })}
                  </span>
                </div>
                {/* Progress bar */}
                <motion.div
                  initial={{ scaleX: 0 }}
                  animate={{ scaleX: 1 }}
                  transition={{ delay: 0.4, duration: 0.6 }}
                  className="origin-left"
                >
                  <div className="h-1.5 w-full overflow-hidden rounded-full bg-zinc-800">
                    <div
                      className={`h-full rounded-full transition-all duration-700 ${(() => {
                        if (!maxLossThreshold || !cumulativeLoss) return 'bg-gradient-to-r from-emerald-500 to-emerald-400'
                        const pct = Number((cumulativeLoss as bigint) * BigInt(100) / (maxLossThreshold as bigint))
                        if (pct > 75) return 'bg-gradient-to-r from-red-500 to-orange-400'
                        if (pct > 40) return 'bg-gradient-to-r from-yellow-500 to-amber-400'
                        return 'bg-gradient-to-r from-emerald-500 to-emerald-400'
                      })()}`}
                      style={{
                        width: maxLossThreshold && cumulativeLoss
                          ? `${Math.min(100, Number((cumulativeLoss as bigint) * BigInt(100) / (maxLossThreshold as bigint)))}%`
                          : '0%'
                      }}
                    />
                  </div>
                </motion.div>
              </div>
            </CardContent>
          </Card>
        </motion.div>
      </motion.div>

      {/* ═══════════════════════════════════
          RIGHT COLUMN — Uniswap-style Card
          ═══════════════════════════════════ */}
      <motion.div variants={itemVariants}>
        <motion.div variants={cardHover} initial="rest" whileHover="hover">
          <Card className="glow-border overflow-hidden">
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="flex items-center gap-2">
                    <Sparkles className="h-4 w-4 text-emerald-400" />
                    Optimize
                  </CardTitle>
                  <CardDescription className="mt-1.5">
                    Deposit USDC and auto-rebalance across Somnia farms
                  </CardDescription>
                </div>
              </div>
            </CardHeader>
            <CardContent className="space-y-5">
              {/* ── Amount Input ── */}
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <label className="text-xs font-medium uppercase tracking-wider text-zinc-500">
                    Amount
                  </label>
                  <span className="text-xs text-zinc-600">
                    Balance: <span className="text-zinc-400 font-mono">{Number(displayUsdc).toLocaleString()} USDC</span>
                  </span>
                </div>
                <div className="relative">
                  <input
                    type="text"
                    inputMode="decimal"
                    value={amount}
                    onChange={(e) => {
                      const val = e.target.value;
                      if (/^\d*\.?\d*$/.test(val)) setAmount(val);
                    }}
                    placeholder="0.00"
                    className="w-full h-14 rounded-xl border border-zinc-800/60 bg-zinc-900/80 pl-4 pr-28 text-xl font-semibold text-zinc-100 placeholder:text-zinc-700 focus:outline-none focus:ring-2 focus:ring-emerald-500/30 focus:border-emerald-500/40 transition-all duration-200 font-mono"
                  />
                  <div className="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-2">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setAmount(displayUsdc)}
                      className="text-xs text-emerald-400 hover:text-emerald-300 hover:bg-emerald-500/10 h-7 px-2"
                    >
                      Max
                    </Button>
                    <div className="flex items-center gap-1.5 rounded-lg bg-zinc-800/60 px-2.5 py-1.5 ring-1 ring-zinc-700/40">
                      <div className="h-5 w-5 rounded-full bg-blue-500 flex items-center justify-center">
                        <span className="text-[10px] font-bold text-white">$</span>
                      </div>
                      <span className="text-sm font-medium text-zinc-200">
                        USDC
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              {/* ── Divider with arrow ── */}
              <div className="relative flex items-center justify-center">
                <div className="absolute inset-0 flex items-center">
                  <div className="w-full border-t border-zinc-800/40" />
                </div>
                <div className="relative flex h-8 w-8 items-center justify-center rounded-lg border border-zinc-800/60 bg-zinc-900">
                  <ArrowRight className="h-3.5 w-3.5 text-zinc-500" />
                </div>
              </div>

              {/* ── Farm Routing Info ── */}
              <div className="rounded-xl bg-zinc-800/20 border border-zinc-700/30 p-4 space-y-2">
                <p className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">
                  How farm routing works
                </p>
                <p className="text-xs text-zinc-500 leading-relaxed">
                  The Somnia Yield Optimizer automatically selects the highest-yielding farm.
                  When the on-chain Keeper detects a better APY, it triggers a <span className="text-emerald-400">YieldUpdated</span> event.
                  Somnia&apos;s reactive precompile catches it and rebalances your capital — no user action needed.
                </p>
                <p className="text-xs text-zinc-600">
                  Current target: <span className="font-mono text-zinc-400">
                    {currentFarm && currentFarm !== '0x0000000000000000000000000000000000000000'
                      ? currentFarm as string
                      : 'Awaiting first rebalance trigger'}
                  </span>
                </p>
              </div>

              {/* ── Summary Row ── */}
              {amount && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: "auto" }}
                  className="rounded-xl bg-zinc-800/30 border border-zinc-800/40 p-3.5 space-y-2"
                >
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-zinc-500">Network</span>
                    <span className="text-zinc-300">Somnia Testnet</span>
                  </div>
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-zinc-500">Gas Fee</span>
                    <span className="text-emerald-400 font-medium">
                      ~0.001 STT
                    </span>
                  </div>
                </motion.div>
              )}

              {/* ── Step indicator — only shown when a deposit flow is active ── */}
              {isLoggedIn && amount && (
                <div className="flex items-center gap-2">
                  {/* Step 1 */}
                  <div className="flex items-center gap-1.5">
                    <div className={`flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold transition-colors duration-300 ${!needsApproval
                      ? 'bg-emerald-500/20 text-emerald-400 ring-1 ring-emerald-500/30'
                      : 'bg-zinc-800 text-zinc-400 ring-1 ring-zinc-700/50'
                      }`}>
                      {!needsApproval ? '✓' : '1'}
                    </div>
                    <span className={`text-xs transition-colors duration-300 ${!needsApproval ? 'text-emerald-400' : 'text-zinc-400'
                      }`}>
                      Approve
                    </span>
                  </div>

                  {/* Connector */}
                  <div className={`h-px flex-1 transition-colors duration-500 ${!needsApproval ? 'bg-emerald-500/40' : 'bg-zinc-800'
                    }`} />

                  {/* Step 2 */}
                  <div className="flex items-center gap-1.5">
                    <div className={`flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold transition-colors duration-300 ${!needsApproval
                      ? 'bg-emerald-500 text-zinc-950 shadow-[0_0_8px_rgba(16,185,129,0.4)]'
                      : 'bg-zinc-800 text-zinc-600 ring-1 ring-zinc-700/50'
                      }`}>
                      2
                    </div>
                    <span className={`text-xs transition-colors duration-300 ${!needsApproval ? 'text-zinc-100 font-medium' : 'text-zinc-600'
                      }`}>
                      Deposit
                    </span>
                  </div>
                </div>
              )}

              {/* ── CTA Button ── */}
              <Button
                variant="glow"
                size="lg"
                className="w-full text-base"
                disabled={!amount || !isLoggedIn || optimizer.isApproving || optimizer.isDepositing}
                onClick={handleOptimize}
              >
                {optimizer.isApproving || optimizer.isDepositing ? (
                  <div className="flex items-center gap-2">
                    <div className="h-4 w-4 animate-spin rounded-full border-2 border-zinc-900 border-t-transparent" />
                    {optimizer.isApproving ? "Approving USDC..." : "Depositing..."}
                  </div>
                ) : !isLoggedIn ? (
                  "Connect Wallet to Optimize"
                ) : needsApproval ? (
                  <>
                    <Sparkles className="mr-2 h-4 w-4" />
                    Approve USDC
                  </>
                ) : (
                  <>
                    <Sparkles className="mr-2 h-4 w-4" />
                    Optimize Yield
                  </>
                )}
              </Button>

              <div className="grid grid-cols-2 gap-3 mt-4">
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full text-xs"
                  disabled={optimizer.isMinting || !isLoggedIn}
                  onClick={() => optimizer.handleMintTestUSDC(parseUnits("1000", 6))}
                >
                  {optimizer.isMinting ? "Minting..." : "💧 Faucet 1k USDC"}
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full text-xs border-red-900/30 hover:bg-red-500/10 text-red-400"
                  disabled={optimizer.isWithdrawing || !isLoggedIn || !optimizer.userShares || (optimizer.userShares as bigint) === BigInt(0)}
                  onClick={handleWithdrawAll}
                >
                  {optimizer.isWithdrawing ? "Withdrawing..." : "Redeem All Shares"}
                </Button>
              </div>

              {/* ── Powered by Somnia badge ── */}
              <div className="flex items-center justify-center gap-2 pt-1">
                <div className="h-px flex-1 bg-zinc-800/60" />
                <span className="flex items-center gap-1.5 text-[11px] font-medium text-zinc-500">
                  <span className="relative flex h-1.5 w-1.5">
                    <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-50" />
                    <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-emerald-500" />
                  </span>
                  Powered by Somnia Reactivity
                </span>
                <div className="h-px flex-1 bg-zinc-800/60" />
              </div>
            </CardContent>
          </Card>
        </motion.div>
      </motion.div>
    </motion.div>
  );
}
