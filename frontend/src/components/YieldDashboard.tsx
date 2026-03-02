"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import {
  Activity,
  TrendingUp,
  DollarSign,
  ShieldCheck,
  ShieldAlert,
  ChevronDown,
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
import { useYieldOptimizer } from "@/hooks/useYieldOptimizer";
import { useAccountAbstraction } from "@/hooks/useAccountAbstraction";

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
   Mock farms for dropdown
   ───────────────────────────────────────── */
const SOMNIA_FARMS = [
  { id: "farm-1", name: "STT-USDC LP Vault", apy: "12.4%" },
  { id: "farm-2", name: "STT Staking Pool", apy: "8.2%" },
  { id: "farm-3", name: "Somnia Blue Chip Index", apy: "15.7%" },
  { id: "farm-4", name: "STT-ETH Reactor", apy: "22.1%" },
];

/* ═════════════════════════════════════════
   Main Dashboard Component
   ═════════════════════════════════════════ */
export default function YieldDashboard() {
  const optimizer = useYieldOptimizer();
  const { isLoggedIn, isSendingOp, sendGaslessOp } = useAccountAbstraction();

  const [amount, setAmount] = useState("");
  const [selectedFarm, setSelectedFarm] = useState(SOMNIA_FARMS[0].id);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);

  const selectedFarmData = SOMNIA_FARMS.find((f) => f.id === selectedFarm)!;

  const handleOptimize = async () => {
    if (!amount || !isLoggedIn) return;
    // TODO: Encode the calldata for YieldOptimizer and send via AA
    await sendGaslessOp(
      "0x0000000000000000000000000000000000000000",
      "0x",
      "0"
    );
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
                <StatRow
                  icon={Activity}
                  label="Active Farm"
                  value={optimizer.currentFarm || "None"}
                  isLoading={optimizer.isLoading}
                  accent="text-cyan-400"
                />
                <StatRow
                  icon={TrendingUp}
                  label="Current APY"
                  value={optimizer.currentAPY}
                  suffix="%"
                  isLoading={optimizer.isLoading}
                  accent="text-emerald-400"
                />
                <StatRow
                  icon={DollarSign}
                  label="Total Value Optimized"
                  value={`$${optimizer.totalValueOptimized}`}
                  isLoading={optimizer.isLoading}
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
                {optimizer.isLoading ? (
                  <Skeleton className="h-6 w-20" />
                ) : (
                  <motion.div
                    initial={{ scale: 0.8, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    transition={{ delay: 0.3 }}
                  >
                    {optimizer.isPaused ? (
                      <span className="inline-flex items-center gap-1.5 rounded-full bg-red-500/10 px-3 py-1 text-xs font-semibold text-red-400 ring-1 ring-red-500/20">
                        <ShieldAlert className="h-3 w-3" />
                        Paused
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-500/10 px-3 py-1 text-xs font-semibold text-emerald-400 ring-1 ring-emerald-500/20">
                        <ShieldCheck className="h-3 w-3" />
                        Active
                      </span>
                    )}
                  </motion.div>
                )}
              </div>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-zinc-500">Cumulative Loss</span>
                  {optimizer.isLoading ? (
                    <Skeleton className="h-4 w-16" />
                  ) : (
                    <span className="text-zinc-300 font-mono tabular-nums">
                      ${optimizer.cumulativeLoss}
                    </span>
                  )}
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-zinc-500">Max Threshold</span>
                  {optimizer.isLoading ? (
                    <Skeleton className="h-4 w-16" />
                  ) : (
                    <span className="text-zinc-300 font-mono tabular-nums">
                      ${optimizer.maxLossThreshold}
                    </span>
                  )}
                </div>
                {/* Progress bar */}
                {!optimizer.isLoading && (
                  <motion.div
                    initial={{ scaleX: 0 }}
                    animate={{ scaleX: 1 }}
                    transition={{ delay: 0.4, duration: 0.6 }}
                    className="origin-left"
                  >
                    <div className="h-1.5 w-full overflow-hidden rounded-full bg-zinc-800">
                      <div
                        className="h-full rounded-full bg-gradient-to-r from-emerald-500 to-emerald-400 transition-all duration-700"
                        style={{
                          width: `${Math.min(
                            (parseFloat(optimizer.cumulativeLoss.replace(/,/g, "")) /
                              parseFloat(optimizer.maxLossThreshold.replace(/,/g, ""))) *
                              100,
                            100
                          )}%`,
                        }}
                      />
                    </div>
                  </motion.div>
                )}
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
                    Balance: <span className="text-zinc-400 font-mono">--</span>
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
                      onClick={() => setAmount("10000")} // placeholder max
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

              {/* ── Farm Selector ── */}
              <div className="space-y-2">
                <label className="text-xs font-medium uppercase tracking-wider text-zinc-500">
                  Target Somnia Farm
                </label>
                <div className="relative">
                  <button
                    onClick={() => setIsDropdownOpen(!isDropdownOpen)}
                    className="w-full h-14 rounded-xl border border-zinc-800/60 bg-zinc-900/80 px-4 flex items-center justify-between hover:border-zinc-700/60 focus:outline-none focus:ring-2 focus:ring-emerald-500/30 transition-all duration-200"
                  >
                    <div className="flex items-center gap-3">
                      <div className="h-8 w-8 rounded-lg bg-gradient-to-br from-emerald-500/20 to-cyan-500/20 flex items-center justify-center ring-1 ring-emerald-500/20">
                        <TrendingUp className="h-4 w-4 text-emerald-400" />
                      </div>
                      <div className="text-left">
                        <div className="text-sm font-medium text-zinc-100">
                          {selectedFarmData.name}
                        </div>
                        <div className="text-xs text-emerald-400">
                          APY {selectedFarmData.apy}
                        </div>
                      </div>
                    </div>
                    <ChevronDown
                      className={`h-4 w-4 text-zinc-500 transition-transform duration-200 ${
                        isDropdownOpen ? "rotate-180" : ""
                      }`}
                    />
                  </button>

                  {/* Dropdown */}
                  {isDropdownOpen && (
                    <motion.div
                      initial={{ opacity: 0, y: -8 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -8 }}
                      transition={{ duration: 0.15 }}
                      className="absolute top-full left-0 right-0 mt-2 z-50 rounded-xl border border-zinc-800/60 bg-zinc-900/95 backdrop-blur-xl shadow-2xl shadow-black/40 overflow-hidden"
                    >
                      {SOMNIA_FARMS.map((farm) => (
                        <button
                          key={farm.id}
                          onClick={() => {
                            setSelectedFarm(farm.id);
                            setIsDropdownOpen(false);
                          }}
                          className={`w-full px-4 py-3 flex items-center justify-between hover:bg-zinc-800/50 transition-colors ${
                            selectedFarm === farm.id ? "bg-zinc-800/30" : ""
                          }`}
                        >
                          <div className="flex items-center gap-3">
                            <div className="h-7 w-7 rounded-md bg-gradient-to-br from-emerald-500/15 to-cyan-500/15 flex items-center justify-center">
                              <TrendingUp className="h-3.5 w-3.5 text-emerald-400" />
                            </div>
                            <span className="text-sm text-zinc-200">
                              {farm.name}
                            </span>
                          </div>
                          <span className="text-xs font-medium text-emerald-400 font-mono">
                            {farm.apy}
                          </span>
                        </button>
                      ))}
                    </motion.div>
                  )}
                </div>
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
                      Gasless ✨
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-zinc-500">Target APY</span>
                    <span className="text-zinc-300 font-mono">
                      {selectedFarmData.apy}
                    </span>
                  </div>
                </motion.div>
              )}

              {/* ── CTA Button ── */}
              <Button
                variant="glow"
                size="lg"
                className="w-full text-base"
                disabled={!amount || !isLoggedIn || isSendingOp}
                onClick={handleOptimize}
              >
                {isSendingOp ? (
                  <div className="flex items-center gap-2">
                    <div className="h-4 w-4 animate-spin rounded-full border-2 border-zinc-900 border-t-transparent" />
                    Optimizing...
                  </div>
                ) : !isLoggedIn ? (
                  "Connect Wallet to Optimize"
                ) : (
                  <>
                    <Sparkles className="mr-2 h-4 w-4" />
                    Optimize Yield (Gasless)
                  </>
                )}
              </Button>

              {/* ── Powered by badge ── */}
              <p className="text-center text-[11px] text-zinc-600">
                Powered by Somnia Reactivity &bull; ERC-4337 Account Abstraction
              </p>
            </CardContent>
          </Card>
        </motion.div>
      </motion.div>
    </motion.div>
  );
}
