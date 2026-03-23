# Keeper — Standalone Mode

This is the autonomous off-chain polling bot. Run this on a server (Render, Railway, etc.)
for continuous, production-style APY monitoring.

## How it works
1. Polls a simulated (or real) APY source every 60 seconds.
2. If deviation exceeds `DEVIATION_THRESHOLD_BPS` (200 bps / 2%), pushes the new APY
   on-chain via `YieldRelayer.pushYieldUpdate()`.
3. Exposes a `/health` HTTP endpoint for uptime monitoring.

## Setup
```bash
cd keeper-standalone
npm install
cp .env.example .env
# Fill in KEEPER_PRIVATE_KEY, RELAYER_CONTRACT_ADDRESS, TARGET_FARM_ADDRESS, SOMNIA_RPC_URL
node index.js
```

## When to use this
Use for continuous automated operation outside of the demo context.
For hackathon demos, use the Next.js God Mode button instead.
