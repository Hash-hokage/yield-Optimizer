import YieldDashboard from "@/components/YieldDashboard";
import { DemoButton } from "@/components/DemoButton";

export default function Home() {
  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 lg:py-12">
      {/* Page Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-bold tracking-tight text-zinc-100 sm:text-3xl">
          Yield Optimizer
        </h1>
        <p className="mt-2 text-sm text-zinc-500 max-w-lg">
          Automated yield rebalancing across Somnia Testnet farms with gasless
          transactions powered by ERC-4337 account abstraction.
        </p>
      </div>

      {/* Dashboard */}
      <YieldDashboard />

      {/* ── God Mode: Demo Trigger for Hackathon Judges ── */}
      <section className="mt-10 flex justify-center">
        <DemoButton />
      </section>
    </div>
  );
}
