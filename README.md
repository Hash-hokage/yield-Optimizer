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
- [Testing](#testing)
- [Network Details](#network-details)
- [License](#license)

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

The reactive pipeline introduces unique security surface areas:

### 1. Callback Spoofing Prevention

```solidity
if (msg.sender != trustedOracle) revert YieldOptimizer__UnauthorizedCallback();
```

Without this check, an attacker could call `onYieldUpdated(999999, maliciousFarm)` directly, tricking the optimizer into rebalancing into a malicious vault.

### 2. RiskGuard Circuit Breaker

```solidity
if (cumulativeLoss >= maxLossThreshold) {
    isPaused = true;
    emit RiskGuardTripped(cumulativeLoss);
}
```

If cumulative losses from reactive rebalances exceed the threshold, the circuit breaker halts all future callbacks — preventing cascading losses during market manipulation or oracle failures.

### 3. Slippage Protection

The `_executeRebalance` function enforces a **1% slippage tolerance** on all DEX swaps using cached reserve snapshots, guarding against sandwich attacks between the reactive event and the rebalance execution.

### 4. Relayer Access Control

Only the `Ownable` owner of the `YieldRelayer` can call `pushYieldUpdate`, preventing unauthorised APY injection. This owner is the Keeper EOA controlled by the off-chain service.

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

```bash
# Deploy YieldRelayer
forge create src/YieldRelayer.sol:YieldRelayer \
  --rpc-url https://api.infra.testnet.somnia.network \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --constructor-args $KEEPER_ADDRESS

# Deploy YieldOptimizer
forge create src/YieldOptimizer.sol:YieldOptimizer \
  --rpc-url https://api.infra.testnet.somnia.network \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --constructor-args $USDC_ADDRESS $PAYMASTER_ADDRESS $RELAYER_ADDRESS $ROUTER_ADDRESS $MAX_LOSS_THRESHOLD
```

### 5. Create Reactivity Subscription

After deploying both contracts, create the subscription that links them (see [Reactivity Subscription Configuration](#reactivity-subscription-configuration)).

### 6. Start the Keeper

```bash
cd keeper
cp .env.example .env  # Configure environment variables
npm start
```

### 7. Start the Frontend

```bash
cd frontend
npm run dev
```

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
