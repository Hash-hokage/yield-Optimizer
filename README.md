# Somnia Yield Optimizer

> Autonomous, event-driven yield optimizer built on **Somnia Testnet** — leveraging Somnia's native **Reactivity** system to eliminate polling and deliver real-time, cross-contract rebalancing with zero human intervention.

---

## Table of Contents

- [Overview](#overview)
- [How Somnia Reactivity Works](#how-somnia-reactivity-works)
- [Architecture](#architecture)
  - [The Reactive Pipeline](#the-reactive-pipeline)
  - [Data Flow Diagram](#data-flow-diagram)
- [Smart Contracts](#smart-contracts)
  - [YieldRelayer.sol — The Event Source](#yieldrelayersol--the-event-source)
  - [YieldOptimizer.sol — The Reactive Handler](#yieldoptimizersol--the-reactive-handler)
  - [ISomniaReactivity.sol — The Reactivity Interface](#isomniaReactivitysol--the-reactivity-interface)
- [Off-Chain Keeper](#off-chain-keeper)
- [Frontend](#frontend)
- [Somnia Gas Considerations](#somnia-gas-considerations)
- [Reactivity Subscription Configuration](#reactivity-subscription-configuration)
- [Security Model](#security-model)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [👨‍⚖️ For Judges: Testing Reactivity Live](#-for-judges-testing-reactivity-live)
- [Testing](#testing)
- [Network Details](#network-details)
- [License](#license)

---

## Live Testnet Demo

| Resource | Link |
|---|---|
| **Frontend (Vercel)** | [https://your-project.vercel.app](https://your-project.vercel.app) |
| **YieldRelayer** | `0x...` |
| **YieldOptimizer** | `0x...` |

---

## Overview

Traditional DeFi yield optimisers rely on off-chain bots that **poll** blockchain state at fixed intervals, burning gas on redundant read calls and suffering latency between yield changes and rebalancing actions.

This project replaces polling with **Somnia Reactivity** — a pub/sub event system baked into the Somnia blockchain itself. When a yield rate changes, the network **pushes** the update directly to the optimizer contract, triggering an instant, autonomous rebalance. The result is a fully reactive pipeline:

```
Off-Chain Keeper → YieldRelayer (emit event) → Somnia Reactive Nodes → YieldOptimizer (callback)
```

No cron jobs. No block-by-block scanning. No wasted gas. The blockchain does the work.

---

## How Somnia Reactivity Works

Somnia Reactivity is a **native event-driven execution model** built into the Somnia blockchain at the validator level. Unlike Ethereum, where contracts must be explicitly called, Somnia validators can:

1. **Detect events** emitted by any contract on-chain.
2. **Bundle state** — read view functions at the event's block height for a consistent snapshot.
3. **Deliver payloads** — automatically invoke callback functions on subscriber contracts in a subsequent block.

This means a smart contract can **subscribe** to events from another contract and receive automatic callbacks — no off-chain infrastructure required for the event routing itself.

### Key Properties

| Property | Detail |
|---|---|
| **Delivery model** | Push-based — validators route events to subscribers |
| **State consistency** | Event data and state reads are from the **same block height** |
| **Execution timing** | Handler runs in the **next block**, not the event's block |
| **Subscription types** | Off-chain (WebSocket) and on-chain (Solidity handlers) |
| **Precompile address** | `0x0000000000000000000000000000000000000100` |

---

## Architecture

### The Reactive Pipeline

This project uses a **four-stage reactive pipeline** to transform off-chain yield data into on-chain rebalancing actions:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SOMNIA YIELD OPTIMIZER                          │
│                                                                       │
│  ┌──────────────┐     ┌──────────────────┐     ┌───────────────────┐  │
│  │              │     │                  │     │                   │  │
│  │  Stage 1     │     │  Stage 2         │     │  Stage 3          │  │
│  │  KEEPER      │────▶│  YIELD RELAYER   │────▶│  SOMNIA REACTIVE  │  │
│  │  (Node.js)   │ tx  │  (Solidity)      │ evt │  NODES            │  │
│  │              │     │                  │     │  (Validators)     │  │
│  └──────────────┘     └──────────────────┘     └─────────┬─────────┘  │
│                                                          │            │
│                                                   callback            │
│                                                          │            │
│                                                          ▼            │
│                                              ┌───────────────────┐    │
│                                              │                   │    │
│                                              │  Stage 4          │    │
│                                              │  YIELD OPTIMIZER  │    │
│                                              │  (Solidity)       │    │
│                                              │  • Verify sender  │    │
│                                              │  • Check circuit  │    │
│                                              │    breaker        │    │
│                                              │  • Profitability  │    │
│                                              │    math           │    │
│                                              │  • Rebalance      │    │
│                                              │  • RiskGuard      │    │
│                                              └───────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow Diagram

```
   Off-Chain                         On-Chain (Somnia Testnet)
   ────────                         ──────────────────────────

   ┌─────────┐    pushYieldUpdate()    ┌────────────────┐
   │ Keeper  │ ──────────────────────▶ │ YieldRelayer   │
   │ index.js│    (every 60s if        │                │
   │         │     deviation > 2%)     │ emit YieldUpdated(newAPY, farm)
   └─────────┘                         └───────┬────────┘
                                                │
                                     ┌──────────▼──────────┐
                                     │  Somnia Validators   │
                                     │  (Reactivity Layer)  │
                                     │                      │
                                     │  Detect YieldUpdated │
                                     │  Route to subscriber │
                                     └──────────┬───────────┘
                                                │
                                     ┌──────────▼──────────┐
                                     │  YieldOptimizer     │
                                     │                     │
                                     │  onYieldUpdated()   │
                                     │  ├─ Access control  │
                                     │  ├─ Circuit breaker │
                                     │  ├─ ΔY > G+S check  │
                                     │  ├─ _executeRebalance│
                                     │  ├─ Gas reimburse   │
                                     │  └─ RiskGuard       │
                                     └─────────────────────┘
```

---

## Smart Contracts

### `YieldRelayer.sol` — The Event Source

**Role:** The on-chain bridge between off-chain data and Somnia's reactive infrastructure.

The `YieldRelayer` is deliberately minimal. Its sole purpose is to accept APY data from the authorised Keeper EOA and **emit a `YieldUpdated` event** that Somnia's reactive nodes will detect:

```solidity
event YieldUpdated(uint256 newAPY, address targetFarm);

function pushYieldUpdate(uint256 _newAPY, address _targetFarm) external onlyOwner {
    currentFarmYields[_targetFarm] = _newAPY;
    emit YieldUpdated(_newAPY, _targetFarm);  // ← Somnia reactivity trigger
}
```

**Why a separate contract?** Separation of concerns:
- The Relayer is the **trusted event source** — its address is hardcoded into the Optimizer as `trustedOracle`.
- The Relayer uses OpenZeppelin's `Ownable` for access control, ensuring only the authorised Keeper can push data.
- The Relayer's event signature (`YieldUpdated(uint256,address)`) is the exact event that the Somnia reactivity subscription monitors.

**Somnia Reactivity Role:**  
This contract is the **publisher** in Somnia's pub/sub model. The `YieldUpdated` event is the trigger that the reactive nodes listen for. Once emitted, validators detect it at the consensus level and route it to any contract subscribed to this event.

---

### `YieldOptimizer.sol` — The Reactive Handler

**Role:** The subscriber contract that **receives** reactive callbacks and executes the rebalancing logic.

When Somnia's reactive nodes detect a `YieldUpdated` event from the `YieldRelayer`, they automatically invoke `onYieldUpdated` on this contract. The full callback flow:

```solidity
function onYieldUpdated(uint256 newAPY, address targetFarm) external {
    // 1. ACCESS CONTROL — verify msg.sender is the trusted oracle (YieldRelayer)
    if (msg.sender != trustedOracle) revert YieldOptimizer__UnauthorizedCallback();

    // 2. CIRCUIT BREAKER — check if RiskGuard has paused operations
    if (isPaused) revert YieldOptimizer__Paused();

    // 3. GAS TRACKING — snapshot gasleft() for reimbursement calculation
    uint256 startGas = gasleft();

    // 4–5. PROFITABILITY MATH
    //   ΔY = expectedYield = balance × newAPY / 10_000
    //   S  = slippage estimate from cached DEX reserves
    //   G  = estimated gas cost via tx.gasprice
    //   Gate: ΔY > (G + S) × 1.10 — only rebalance if profitable

    // 6. REBALANCE — withdraw → route → swap → deposit
    _executeRebalance(targetFarm);

    // 7. GAS REIMBURSEMENT — reimburse via paymaster
    // 8. RISKGUARD — accumulate losses, trip circuit breaker if threshold breached
}
```

**Key design decisions for Somnia Reactivity:**

1. **`msg.sender` verification** — Critical. Without this check, anyone could call `onYieldUpdated` with fabricated APY data. The `trustedOracle` is the `YieldRelayer` contract address, which Somnia's reactive nodes use as the `msg.sender` when routing the event.

2. **Graceful returns, not reverts** — If the rebalance isn't profitable (`ΔY ≤ totalCost`), the function returns gracefully instead of reverting. This prevents wasting the reactive node's gas budget on failed callbacks.

3. **Circuit breaker** — The `isPaused` flag halts all reactive callbacks if cumulative losses exceed the `maxLossThreshold`, preventing cascading losses during adverse market conditions.

---

### `ISomniaReactivity.sol` — The Reactivity Interface

**Role:** Defines the contract between the reactive infrastructure and the consumer.

This interface specifies two concerns:

1. **Subscription** — The `subscribe(address, bytes32)` function that registers interest in a specific event from a specific contract.
2. **Callback** — The `onYieldUpdated(uint256, address)` handler that the reactive nodes invoke.

```solidity
interface ISomniaReactivity {
    event Subscribed(address indexed subscriber, address indexed source, bytes32 indexed eventSignature);
    function subscribe(address contractAddress, bytes32 eventSignature) external;
    function onYieldUpdated(uint256 newAPY, address tokenAddress) external;
}
```

> **Note on pattern choice:** Somnia also provides an official `SomniaEventHandler` base contract (from the `@somnia-chain/reactivity-contracts` package) with a generic `_onEvent(address, bytes32[], bytes)` handler and a precompile at `0x0100`. This project uses a **custom typed callback** (`onYieldUpdated`) for stronger type safety and clearer semantics. Both approaches are valid.

---

## Off-Chain Keeper

The `keeper/` directory contains a Node.js service that acts as the data bridge between off-chain APY sources and on-chain contracts.

### How It Works

```
┌──────────────────────────────────────────────────────┐
│                     keeper/index.js                   │
│                                                      │
│   Engine 1: Express Health Server (port 3000)        │
│   └─ GET / → { status: "ok", uptime: ... }          │
│                                                      │
│   Engine 2: Blockchain Polling Loop (every 60s)      │
│   ├─ 1. fetchSimulatedAPY()  → random 300-800 bps   │
│   ├─ 2. Check deviation from last pushed value       │
│   ├─ 3. If deviation > 200 bps (2%):                │
│   │      └─ relayer.pushYieldUpdate(newAPY, farm)    │
│   └─ 4. Wait for tx confirmation                    │
└──────────────────────────────────────────────────────┘
```

**Key behaviour:**
- **Polling interval:** 60 seconds
- **Deviation threshold:** 200 basis points (2%) — prevents spamming the chain with insignificant updates
- **Error recovery:** Full `try/catch` wraps each tick so transient RPC errors don't crash the process
- **Tx confirmation:** Waits for on-chain confirmation before updating local state, ensuring consistency

> **Production note:** The `fetchSimulatedAPY()` function currently returns random data for testnet demonstration. In production, this would query DeFi aggregator APIs (e.g., DefiLlama, Zapper) for live yield data.

### Environment Variables

```bash
KEEPER_PRIVATE_KEY=0x...        # Keeper EOA private key
RELAYER_CONTRACT_ADDRESS=0x...  # Deployed YieldRelayer address
TARGET_FARM_ADDRESS=0x...       # Target farm/vault address
SOMNIA_RPC_URL=https://api.infra.testnet.somnia.network
PORT=3000                       # Health server port (optional)
```

---

## Frontend

The `frontend/` directory contains a Next.js 14 dashboard providing a premium DeFi interface for monitoring the optimizer's state:

- **Portfolio Overview** — Active farm, current APY, total value optimised
- **RiskGuard Status** — Live `isPaused` state with cumulative loss progress bar
- **Optimize Card** — Uniswap-style interactive card for triggering gasless optimisations via ERC-4337 Account Abstraction
- **Real-time data** — Connected to the Somnia Testnet via viem (chain ID `50312`)

---

## Somnia Gas Considerations

Somnia's gas model diverges significantly from Ethereum. These differences directly impact how we design reactive handlers:

| Opcode | Ethereum | Somnia | Factor |
|---|---|---|---|
| Cold `SLOAD` | ~2,100 gas | ~1,000,000 gas | **~476×** |
| `LOG` opcodes | Baseline | ~13× Ethereum | **~13×** |

### Impact on This Project

The `onYieldUpdated` callback is classified as a **complex handler** because it:
- Performs **multiple cold storage reads** (`cachedReserveUSDC`, `isPaused`, `cumulativeLoss`, `maxLossThreshold`)
- Executes **cross-contract calls** (DEX router swap, vault deposit/withdraw)
- Emits events (`OptimizerExecuted`, `RiskGuardTripped`)

This means the reactive subscription backing this callback must be configured with high gas limits (see next section).

### Design Mitigations

1. **Storage packing** — `owner` (address, 20 bytes) and `isPaused` (bool, 1 byte) share a single storage slot, reducing cold reads from 2 to 1.
2. **Cached reserves** — `cachedReserveUSDC` and `cachedReserveTarget` avoid repeated external calls to the DEX pool.
3. **Graceful returns** — Non-profitable callbacks return early without emitting events, saving gas on `LOG` opcodes.
4. **Exact approvals** — `SafeERC20.forceApprove()` sets the precise amount needed for each swap, avoiding unnecessary storage writes.

---

## Reactivity Subscription Configuration

When creating the on-chain subscription that connects the `YieldRelayer`'s `YieldUpdated` event to the `YieldOptimizer`'s `onYieldUpdated` callback, use these parameters:

```typescript
import { SDK } from '@somnia-chain/reactivity'
import { parseGwei, keccak256, toBytes } from 'viem'

await sdk.createSoliditySubscription({
  handlerContractAddress: '<YieldOptimizerAddress>',
  emitter: '<YieldRelayerAddress>',
  eventTopics: [keccak256(toBytes('YieldUpdated(uint256,address)'))],

  // ⚠️ CRITICAL: Gas misconfiguration is the #1 cause of "reactivity not working"
  priorityFeePerGas: parseGwei('3'),   // 3 gwei — complex handler needs higher tip
  maxFeePerGas: parseGwei('15'),       // 15 gwei ceiling
  gasLimit: 3_000_000n,               // Complex: swaps + vault deposits + state reads

  isGuaranteed: true,                  // Retry if block is full
  isCoalesced: false                   // Process each event individually
})
```

> **Common mistake:** Passing raw numbers like `10n` for `priorityFeePerGas` — that's 10 **wei**, essentially zero. Validators will silently skip the subscription. Always use `parseGwei()`.

### Required Minimum Balance

The subscription owner's EOA must maintain a minimum balance of **32 STT** (Somnia Testnet Token) for the subscription to remain active.

---

## Security Model

The reactive pipeline introduces unique security surface areas. These defenses were hardened through a full internal audit (see patches C-01/C-02, H-01–H-03, M-01–M-04, L-01–L-02).

### 1. Callback Spoofing Prevention

```solidity
if (msg.sender != trustedOracle) revert YieldOptimizer__UnauthorizedCallback();
```

Without this check, an attacker could call `onYieldUpdated(999999, maliciousFarm)` directly, tricking the optimizer into rebalancing into a malicious vault.

### 2. Farm Whitelist (`allowedFarms`)

Only farms explicitly whitelisted by the owner via `setFarmAllowed(address, bool)` can be targeted by `onYieldUpdated`. This prevents a compromised Keeper from routing funds into a malicious ERC-4626 vault:

```solidity
if (!allowedFarms[targetFarm]) revert YieldOptimizer__FarmNotWhitelisted();
```

### 3. RiskGuard Circuit Breaker (Total Portfolio Value)

The RiskGuard now calculates **Total Portfolio Value** (`USDC balance + underlying farm shares via convertToAssets`) rather than raw USDC balance alone. This prevents false positives that previously tripped the circuit breaker during normal rebalances where USDC was legitimately converted to farm shares:

```solidity
uint256 portfolioBefore = _getPortfolioValue(); // USDC + farm shares value
// ... rebalance ...
uint256 portfolioAfter = _getPortfolioValue();
if (portfolioAfter < portfolioBefore) {
    cumulativeLoss += portfolioBefore - portfolioAfter;
    if (cumulativeLoss >= maxLossThreshold) {
        isPaused = true;
        emit RiskGuardTripped(cumulativeLoss);
    }
}
```

### 4. Dynamic Slippage Protection

The `_executeRebalance` function enforces a **1% slippage tolerance** by querying the DEX router's `getAmountsOut` at execution time for a **live on-chain quote**, rather than relying on stale cached reserve snapshots. This eliminates the stale-reserve manipulation vector entirely:

```solidity
uint256[] memory expectedAmounts = router.getAmountsOut(swapAmount, path);
uint256 minAmountOut = (expectedAmounts[expectedAmounts.length - 1] * 99) / 100;
```

### 5. Relayer Access Control

Only the `Ownable` owner of the `YieldRelayer` can call `pushYieldUpdate`, preventing unauthorised APY injection. This owner is the Keeper EOA controlled by the off-chain service.

### 6. Admin Lifelines

| Function | Purpose |
|---|---|
| `unpause()` | Resume operations after RiskGuard has tripped |
| `resetCumulativeLoss()` | Zero the loss counter after root cause is addressed |
| `emergencyWithdraw(token, amount)` | Rescue stuck ERC-20 tokens |
| `emergencyWithdrawETH()` | Drain ETH in an emergency |
| `updateCachedReserves(usdc, target)` | Refresh cached reserves for profitability math |

All admin functions are gated by OpenZeppelin's `Ownable` (replacing the previous custom `owner` + `onlyOwner` pattern).

---

## Project Structure

```
somnia-yield-optimizer/
├── src/
│   ├── YieldOptimizer.sol          ← Reactive handler — receives callbacks
│   ├── YieldRelayer.sol            ← Event source — emits YieldUpdated
│   ├── interfaces/
│   │   ├── ISomniaReactivity.sol   ← Reactivity interface (subscribe + callback)
│   │   ├── IDEXRouter.sol          ← Uniswap V2 router interface
│   │   ├── IUniswapV2Factory.sol   ← Factory for pair lookups
│   │   └── IYieldFarm.sol          ← ERC-4626 vault interface
│   └── mocks/
│       ├── MockDEX.sol             ← DEX router mock for testing
│       ├── MockERC20.sol           ← ERC-20 token mock
│       ├── MockOracle.sol          ← Trusted oracle mock
│       ├── MockUniswapV2Factory.sol← Factory mock
│       └── MockYieldFarm.sol       ← ERC-4626 vault mock
├── test/
│   ├── unit/                       ← Unit tests (profitable/unprofitable rebalances)
│   ├── security/                   ← Security tests (access control, slippage, circuit breaker)
│   └── invariant/                  ← Invariant/fuzz tests (math, max loss threshold)
├── keeper/
│   ├── index.js                    ← Off-chain APY polling + relay service
│   └── package.json
├── frontend/
│   └── src/
│       ├── lib/viemConfig.ts       ← Somnia Testnet chain config (ID: 50312)
│       ├── hooks/useYieldOptimizer.ts ← Contract state reader hook
│       ├── hooks/useAccountAbstraction.ts ← ERC-4337 AA placeholder
│       └── components/             ← Dashboard UI components
└── foundry.toml                    ← Foundry build configuration
```

---

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast)
- Node.js ≥ 18
- STT tokens from the [Somnia Testnet Faucet](https://testnet.somnia.network)

### 1. Clone & Install

```bash
git clone https://github.com/Hash-hokage/yield-Optimizer.git
cd yield-Optimizer

# Install Foundry dependencies
forge install

# Install Keeper dependencies
cd keeper && npm install && cd ..

# Install Frontend dependencies
cd frontend && npm install && cd ..
```

### 2. Build Contracts

```bash
forge build
```

### 3. Run Tests

```bash
# Unit tests
forge test --match-path test/unit/*.sol -vvv

# Security tests
forge test --match-path test/security/*.sol -vvv

# Invariant/fuzz tests
forge test --match-path test/invariant/*.sol -vvv
```

### 4. Deploy (Somnia Testnet)

> **OpSec:** We use Foundry's **encrypted keystore** instead of plaintext `.env` private keys. Your key is stored locally under a password and never touches disk in cleartext.

#### 4.1. Setup Deployer Account

```bash
cast wallet import deployer --interactive
```

This prompts you to paste your private key and set a password. The key is encrypted and stored locally in Foundry's keystore.

#### 4.2. Broadcast & Subscribe

```bash
forge script script/Deploy.s.sol \
  --rpc-url https://api.infra.testnet.somnia.network \
  --broadcast \
  --account deployer
```

This **atomic deployment script** performs all of the following in one transaction batch:
1. Deploys `YieldRelayer` and `YieldOptimizer`
2. Creates the **32 STT reactivity subscription** on the Somnia Precompile (`0x0100`)
3. Links the contracts via the subscription's event routing

You will be prompted for your keystore password. All deployed addresses are logged to the console for `.env` and frontend configuration.

### 5. Start the Keeper

```bash
cd keeper
cp .env.example .env  # Configure environment variables
npm start
```

### 6. Start the Frontend

```bash
cd frontend
npm run dev
```

---

## 👨‍⚖️ For Judges: Testing Reactivity Live

The system has two categories of actions:

### User Actions

Visit the **[Vercel Frontend](https://your-project.vercel.app)** and deposit USDC into the Optimizer. The dashboard displays live portfolio value, current farm, APY, and RiskGuard status.

### System Actions (Reactivity)

APY updates are normally pushed by our off-chain Keeper every 60 seconds. However, to test the full reactive pipeline **instantly** without waiting, use this "God Mode" command to force an update:

```bash
# Force a yield update to trigger the reactive bot
cast send <YIELD_RELAYER_ADDRESS> \
  "pushYieldUpdate(uint256,address)" \
  750 <TARGET_FARM_ADDRESS> \
  --rpc-url https://api.infra.testnet.somnia.network \
  --private-key <TEST_KEEPER_KEY>
```

**What happens next:**
1. The `YieldRelayer` emits a `YieldUpdated` event
2. Somnia's reactive nodes detect the event and route it to the `YieldOptimizer`
3. The optimizer runs `onYieldUpdated` — profitability check → rebalance → RiskGuard
4. The **Vercel UI automatically updates** within a few seconds (no refresh needed)

> **Tip:** The APY value `750` means 7.50% in basis points. Try different values (e.g., `300` for 3%, `1500` for 15%) to see the profitability gate accept or reject rebalances.

---

## Testing

| Test Suite | File | What It Verifies |
|---|---|---|
| Unit | `test/unit/YieldOptimizer.unit.t.sol` | Profitable and unprofitable rebalance paths |
| Security | `test/security/YieldOptimizer.security.t.sol` | Access control, slippage protection, circuit breaker |
| Invariant | `test/invariant/YieldOptimizer.invariant.t.sol` | Stateless fuzz (math) + stateful invariant (`cumulativeLoss ≤ maxLossThreshold` while unpaused) |

---

## Network Details

| Property | Value |
|---|---|
| **Chain ID** | `50312` |
| **RPC (HTTP)** | `https://api.infra.testnet.somnia.network` |
| **RPC (WebSocket)** | `wss://api.infra.testnet.somnia.network` |
| **Block Explorer** | `https://shannon-explorer.somnia.network` |
| **Native Token** | STT (Somnia Testnet Token), 18 decimals |
| **Faucet** | `https://testnet.somnia.network` |
| **Reactivity Precompile** | `0x0000000000000000000000000000000000000100` |
| **Min Balance for Subscriptions** | 32 STT |

---

## License

MIT
