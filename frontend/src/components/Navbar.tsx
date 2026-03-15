"use client";

import { motion } from "framer-motion";
import { Zap } from "lucide-react";
import { ConnectButton } from "@rainbow-me/rainbowkit";

export default function Navbar() {
  return (
    <motion.nav
      initial={{ y: -20, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.5, ease: "easeOut" }}
      className="sticky top-0 z-50 glass-nav"
    >
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 items-center justify-between">
          {/* Logo */}
          <div className="flex items-center gap-2.5">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-500/10 ring-1 ring-emerald-500/20">
              <Zap className="h-4 w-4 text-emerald-400" />
            </div>
            <span className="text-lg font-semibold tracking-tight text-zinc-100">
              Somnia
              <span className="text-emerald-400"> Yield</span>
            </span>
          </div>

          {/* Right Side — Wallet Connect */}
          <ConnectButton />
        </div>
      </div>
    </motion.nav>
  );
}
