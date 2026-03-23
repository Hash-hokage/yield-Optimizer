# Keeper — Next.js API Mode (God Mode)

This keeper is embedded in the Next.js frontend as an API route:
`frontend/src/app/api/trigger-rebalance/route.ts`

It is triggered manually by the "Simulate APY Spike" button in the dashboard UI.
It decrypts a keystore in-memory, generates a random APY, and pushes it on-chain.

## When to use this
Use during hackathon demos to let judges trigger a rebalance instantly without
waiting for the 60-second polling interval in the standalone keeper.
