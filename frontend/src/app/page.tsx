import YieldDashboard from "@/components/YieldDashboard";
import { DemoButton } from "@/components/DemoButton";
import { Zap, ArrowDown } from "lucide-react";

export default function Home() {
  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">

      {/* ── Hero ── */}
      <section className="relative flex flex-col items-center text-center pt-16 pb-12">
        {/* Ambient glow behind hero */}
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(ellipse_60%_40%_at_50%_0%,rgba(16,185,129,0.07),transparent)]" />

        {/* Badge */}
        <div className="inline-flex items-center gap-2 rounded-full border border-emerald-500/20 bg-emerald-500/5 px-3.5 py-1.5 text-xs font-medium text-emerald-400 mb-6">
          <span className="relative flex h-2 w-2">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
            <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500" />
          </span>
          Live on Somnia Testnet
        </div>

        {/* Headline */}
        <h1 className="text-4xl sm:text-5xl font-bold tracking-tight text-zinc-100 max-w-2xl leading-tight">
          Autonomous Yield
          <span className="block text-transparent bg-clip-text bg-gradient-to-r from-emerald-400 to-cyan-400">
            Powered by Reactivity
          </span>
        </h1>

        <p className="mt-4 text-base text-zinc-400 max-w-xl leading-relaxed">
          Deposit USDC once. Somnia&apos;s native on-chain reactivity automatically
          routes your capital to the highest-yielding farm — no polling,
          no manual execution, no gas wasted.
        </p>

        {/* Pipeline visual */}
        <div className="mt-8 flex items-center gap-2 text-xs text-zinc-500 flex-wrap justify-center">
          {[
            { label: "Keeper", color: "text-zinc-400" },
            { label: "YieldRelayer", color: "text-blue-400" },
            { label: "Somnia Precompile", color: "text-violet-400" },
            { label: "YieldOptimizer", color: "text-emerald-400" },
          ].map((step, i, arr) => (
            <span key={step.label} className="flex items-center gap-2">
              <span className={`font-medium ${step.color}`}>{step.label}</span>
              {i < arr.length - 1 && (
                <Zap className="h-3 w-3 text-zinc-700 shrink-0" />
              )}
            </span>
          ))}
        </div>

        {/* God Mode Button — centrepiece */}
        <div className="mt-10">
          <DemoButton />
        </div>

        {/* Scroll hint */}
        <div className="mt-10 flex flex-col items-center gap-1.5 text-zinc-600">
          <span className="text-xs">View your portfolio below</span>
          <ArrowDown className="h-3.5 w-3.5 animate-bounce" />
        </div>
      </section>

      {/* ── Dashboard ── */}
      <section className="pb-16">
        <YieldDashboard />
      </section>

    </div>
  );
}
