"use client";

import { motion } from "framer-motion";
import { Zap, Wallet, LogOut, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAccountAbstraction } from "@/hooks/useAccountAbstraction";
import { useState } from "react";

export default function Navbar() {
  const { isLoggedIn, userAddress, isLoggingIn, login, logout } =
    useAccountAbstraction();
  const [showEmailInput, setShowEmailInput] = useState(false);
  const [email, setEmail] = useState("");

  const handleConnect = async () => {
    if (showEmailInput && email) {
      await login(email);
      setShowEmailInput(false);
      setEmail("");
    } else {
      setShowEmailInput(true);
    }
  };

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

          {/* Right Side — Auth */}
          <div className="flex items-center gap-3">
            {isLoggedIn ? (
              <>
                <div className="hidden sm:flex items-center gap-2 rounded-xl border border-zinc-800/60 bg-zinc-900/50 px-3 py-1.5">
                  <div className="h-2 w-2 rounded-full bg-emerald-400 animate-pulse" />
                  <span className="text-sm text-zinc-400 font-mono">
                    {userAddress}
                  </span>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={logout}
                  className="text-zinc-500 hover:text-zinc-200"
                >
                  <LogOut className="h-4 w-4" />
                </Button>
              </>
            ) : (
              <div className="flex items-center gap-2">
                {showEmailInput && (
                  <motion.div
                    initial={{ width: 0, opacity: 0 }}
                    animate={{ width: "auto", opacity: 1 }}
                    className="overflow-hidden"
                  >
                    <input
                      type="email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      placeholder="you@email.com"
                      onKeyDown={(e) => e.key === "Enter" && handleConnect()}
                      className="h-10 w-48 rounded-xl border border-zinc-800/60 bg-zinc-900/50 px-3 text-sm text-zinc-100 placeholder:text-zinc-600 focus:outline-none focus:ring-1 focus:ring-emerald-500/40 transition-all"
                    />
                  </motion.div>
                )}
                <Button
                  variant="outline"
                  onClick={handleConnect}
                  disabled={isLoggingIn}
                  className="gap-2"
                >
                  {isLoggingIn ? (
                    <div className="h-4 w-4 animate-spin rounded-full border-2 border-zinc-400 border-t-transparent" />
                  ) : showEmailInput ? (
                    <Mail className="h-4 w-4" />
                  ) : (
                    <Wallet className="h-4 w-4" />
                  )}
                  <span className="hidden sm:inline">
                    {isLoggingIn
                      ? "Connecting..."
                      : showEmailInput
                      ? "Login with Email"
                      : "Connect Wallet"}
                  </span>
                </Button>
              </div>
            )}
          </div>
        </div>
      </div>
    </motion.nav>
  );
}
