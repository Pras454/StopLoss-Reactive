# Reactive Network — Research for the Reactive Omni Buildathon (DoraHacks)

Researched 19 Nov 2026 (WIB) from official docs (dev.reactive.network), official blog,
GitHub (Reactive-Network org), and builder runbooks. All URLs/addresses below were read
live from those sources on that date.

Event: Reactive Omni Buildathon — https://dorahacks.io/hackathon/reactive-omni-buildathon
Prize $5,500 paid in REACT token. Deadline 6 Dec 2026 03:00 WIB. Submission stage open.
Note: "Omni" in the event name matches the new Omni contract model below — build with the
Omni model, NOT the legacy RVM model.

## 1. What Reactive Network is

- EVM-compatible execution layer (by PARSIQ) for **event-driven, cross-chain automation**.
  Consensus: CometBFT, instant finality (no reorgs), ~1s block times.
- **Reactive Smart Contracts (RSCs / "reactive contracts")**: ordinary Solidity contracts
  that subscribe to event logs on any supported chain. When a matching log appears, the
  network's system contract calls the contract's `react()` function — no user tx, no
  off-chain bot (inversion of control). Inside `react()` the contract can update state,
  change subscriptions, or request a **callback** — a transaction the network delivers
  to a contract on a destination chain.
- Flow: event on origin chain → validator posts reactive tx → system contract calls
  `react(log)` on Reactive → contract requests callback → Reactive Signer posts callback
  tx through the destination chain's **callback proxy** → callback contract executes.
- Typical uses: stop-loss / take-profit orders, liquidation protection, portfolio
  rebalancing, cross-chain swaps, scheduled (CRON) automation, prediction-market payouts.

## 2. Legacy vs Omni — CRITICAL: use the Omni model

The docs describe a migration ("Reactive Legacy vs Reactive Omni"). Legacy contracts keep
working, but **all new contracts must use the Omni model**:

| | Legacy (old) | Omni (current — use this) |
|---|---|---|
| `react()` guard | `vmOnly` modifier, RVM dual state | `onlySystem` modifier, single network |
| Subscribe | `service.subscribe(...)` inside `if (!vm)` | `SYSTEM.subscribe(...)` directly |
| Callback | emit `Callback` event (deprecated, still works) | `SYSTEM.requestCallbackV_1_0({...})` |
| System contract | `0x0000000000000000000000000000000000fffFfF` | `0x8888888888888888888888888888888888888888` |
| Tooling | custom RVM RPC methods | standard EVM: Foundry `cast` works out of the box |

The old system-contract address still exists only as the emitter of CRON events (see §7).
Do NOT copy code from old tutorials/blog posts that use `vmOnly`, `rvmIdOnly`, or the
`Callback` event — they are the legacy pattern.

## 3. Networks

### Reactive Mainnet
- Chain ID: **1597** (0x63d)
- RPC: https://mainnet-rpc.rnk.dev/
- Explorer: https://reactscan.net/
- Currency: REACT (native gas token)

### Lasna Testnet (the testnet to build on)
- Chain ID: **5318007**
- RPC: https://lasna-rpc.rnk.dev/
- Explorer: https://lasna.reactscan.net/
- Currency: **lREACT** (testnet REACT)
- System contract (both networks): `0x8888888888888888888888888888888888888888`

### Kopli — do NOT use
Kopli (chain 5318008, kopli-rpc.rnk.dev, kopli.reactscan.net) is an older testnet still
referenced in some third-party pages. Current official docs name **Lasna** as the testnet.
Build on Lasna.

## 4. Faucet — how to get testnet lREACT

There is NO web-form faucet. lREACT is obtained by sending Sepolia ETH to a faucet
contract (1 ETH → 100 lREACT):
- Ethereum Sepolia faucet: `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`
- Base Sepolia faucet: `0x2afaFD298b23b62760711756088F75B7409f5967`
- Max **5 ETH per transaction** (max 500 lREACT); amounts above 5 ETH are LOST.
- Plain ETH transfer works (MetaMask), or call `request(address)`:

```bash
cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 \
  --rpc-url $ETHEREUM_SEPOLIA_RPC --private-key $ETHEREUM_SEPOLIA_PRIVATE_KEY \
  "request(address)" $WALLET_ADDR --value 0.1ether
# 0.1 Sepolia ETH -> 10 lREACT, credited to $WALLET_ADDR on Lasna
```

So the funding path is: get Sepolia ETH (Alchemy/QuickNode/Google Cloud faucets) →
send to the faucet contract → lREACT lands on Lasna. Budget: a few lREACT covers many
react() executions; fund contracts generously (see §8 — debt stops execution).

## 5. Origins & Destinations (supported chains + callback proxies)

Origin = chain whose events you listen to. Destination = chain where callbacks land.
**Mainnets and testnets must NOT be mixed** — testnet origin ⇒ testnet destination.
Source: https://dev.reactive.network/origins-and-destinations

### Testnet chains (for Lasna builds)
| Chain | Chain ID | Callback proxy |
|---|---|---|
| Base Sepolia | 84532 | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` |
| Ethereum Sepolia | 11155111 | `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` |
| Reactive Lasna | 5318007 | `0x8888888888888888888888888888888888888888` |
| Unichain Sepolia | 1301 | `0x775c9B990ADe401060B78D0e98684eEf8d2466C1` |

Note: there is NO BSC testnet, NO Polygon Amoy, NO HyperEVM testnet (998) as a Lasna
destination (HyperEVM 999 is mainnet-only). Testnet cross-chain demos must use
Sepolia / Base Sepolia / Unichain Sepolia / Lasna itself. (A builder runbook confirms
Lasna → HyperEVM testnet 998 is NOT reachable; the fully auto-wired loop is mainnet-only.)

### Mainnet chains
| Chain | Chain ID | Callback proxy |
|---|---|---|
| Arbitrum | 42161 | `0xaee8d2deBaB5bE353bfec167C58a549923892e11` |
| Avalanche | 43114 | `0x8bdfC7e564B90b31c49Cf1079d4c44400F4e14B4` |
| Base | 8453 | `0xCc780DdE33f56f55dE778D42c930959374a4a068` |
| BSC | 56 | `0xfc41eE9d3A836b41399BEcce83b06B3e5650f3BB` |
| Ethereum | 1 | `0xFCE1F192F489c988392aBC16E91e359d540d94Fe` |
| HyperEVM | 999 | `0x754120EC7a6eF81E4c5c835AA603C63Da64693E6` |
| Reactive | 1597 | `0x8888888888888888888888888888888888888888` |
| Robinhood Chain | 4663 | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` |
| Unichain | 130 | `0x754120EC7a6eF81E4c5c835AA603C63Da64693E6` |

A destination contract authenticates a callback by checking `msg.sender` is the
callback proxy AND the injected first payload argument is the authorized reactive
contract (see §6).

## 6. Writing + deploying a reactive contract

Stack: **Solidity ^0.8.29, Foundry** (forge/cast work out of the box; no custom RPC
methods needed). Base library: `Reactive-Network/reactive-lib-omni`
(https://github.com/Reactive-Network/reactive-lib-omni) — import remapping `@reactive/`.

Install (standard Foundry pattern, inferred from the `@reactive/...` import paths in
the official docs — the repo README is empty, so verify the remapping after install):

```bash
forge install Reactive-Network/reactive-lib-omni
# foundry.toml remapping: @reactive/=lib/reactive-lib-omni/
```

### Minimal reactive contract (Omni model, from official docs)

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

contract MyReactive is AbstractReactive {
    uint256 private immutable _originChainId;
    address private immutable _originContract;
    uint256 private immutable _topic0;

    // `payable` so the contract can be funded at deployment.
    constructor(uint256 originChainId_, address originContract_, uint256 topic0_) payable {
        _originChainId = originChainId_;
        _originContract = originContract_;
        _topic0 = topic0_;
        SYSTEM.subscribe(
            originChainId_, originContract_, topic0_,
            REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // Your logic here. Route on log_.topic0 / log_.opCode.
    }
}
```

What `AbstractReactive` gives you: `SYSTEM` (system contract), `REACTIVE_IGNORE`
(wildcard topic value `0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad`),
`onlySystem` (reverts `NotAuthorized` for non-system callers), `LogRecord` struct,
plus `AbstractPayer` (`pay()`, `_coverDebt()`, payable `receive()`).

### Subscriptions

```solidity
SYSTEM.subscribe(chainId_, contract_, topic0_, topic1_, topic2_, topic3_);
SYSTEM.unsubscribe(chainId_, contract_, topic0_, topic1_, topic2_, topic3_);
```

- Wildcards: `chainId_ = 0` (any chain), `contract_ = address(0)` (any contract),
  any topic = `REACTIVE_IGNORE`. **At least one criterion must be specific.**
- Equality only — no ranges/comparisons. No OR within one subscription; call
  `subscribe()` once per combination. Duplicates behave as one (and waste gas).
- Subscriptions live in the node, NOT in contract storage — you cannot read them
  back on-chain; track them yourself.
- Can subscribe/unsubscribe at any time, including from inside `react()`.
  `unsubscribe()` must match all six arguments exactly or it fails silently.

### The LogRecord struct passed to react()

```solidity
struct LogRecord {
    uint256 chainId;
    address contractAddress;
    uint256 topic0;
    uint256 topic1;
    uint256 topic2;
    uint256 topic3;
    bytes data;          // ABI-encoded NON-indexed params only
    uint256 blockNumber;
    uint256 opCode;      // number of topics in the original log (LOG0..LOG4)
    uint256 blockHash;   // uint256, not bytes32 — cast to compare
    uint256 txHash;      // uint256, not bytes32
    uint256 logIndex;
}
```

Routing pattern: check `log_.topic0` first, then `log_.opCode` before decoding
`log_.data` (e.g. ERC-20 Transfer = LOG3, amount in `data`; unindexed params would
arrive packed in `data`). A zero topic does NOT prove fewer topics (a mint's
Transfer has `from = address(0)`) — `opCode` is the reliable count.

### Requesting a callback (from inside react() or any external method)

```solidity
uint64 private constant CALLBACK_GAS_LIMIT = 1000000;

function _requestCallback(uint256 chainId_, address recipient_, uint256 value_) internal {
    // FIRST argument MUST be an address placeholder (address(0)): the network
    // overwrites the first 160 bits of the payload with the requesting reactive
    // contract's address. Forgetting this is the most common way to break a callback.
    bytes memory payload = abi.encodeWithSignature(
        "myCallback(address,uint256)", address(0), value_
    );
    SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({
        chainId: chainId_,
        recipient: recipient_,
        gasLimit: CALLBACK_GAS_LIMIT,
        payload: payload
    }));
}
```

`CallbackConfiguration_V_1_0 { uint256 chainId; address recipient; uint64 gasLimit; bytes payload; }`
(V_1_0 is the only callback version today.) Requesting a callback emits a
`CallbackRequest(chainId, sender, recipient, version, configuration)` event the
network picks up. Emitting the legacy `Callback` event still works but is deprecated.

### Minimal callback contract (destination chain)

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

contract MyCallback is AbstractCallback {
    event Handled(address indexed reactive_, uint256 value_);

    constructor(IPayable callbackProxy_, address callbackSender_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {}

    function myCallback(address reactive_, uint256 value_)
        external
        onlyServiceProvider          // caller must be the callback proxy
        onlyCallbackSender(reactive_) // injected address must be the authorized RSC
    {
        emit Handled(reactive_, value_);
    }
}
```

- Use BOTH modifiers, always: without `onlyServiceProvider` anyone can call directly
  and fake the sender; without `onlyCallbackSender` any reactive contract can drive
  your callback through the legitimate proxy.
- A contract CANNOT be both reactive and callback (single immutable `_SERVICE_PROVIDER`
  in `AbstractPayer`; inheriting both won't compile).
- Callback contracts are funded in the DESTINATION chain's native token (ETH on
  Sepolia, etc.), never REACT.

### Deployment order (mandatory — breaks the address chicken-and-egg)

1. Deploy the reactive contract on Reactive (Lasna for testnet).
2. Deploy the callback contract on the destination chain, passing the callback proxy
   address + the reactive contract's address (`callbackSender_` is immutable —
   getting it wrong means redeploying).
3. Set the recipient on the reactive contract through an owner-only setter.
4. Fund both: reactive contract in REACT/lREACT, callback contract in destination
   native token.

### Deploy + verify (Foundry, from official docs)

```bash
forge create --broadcast --rpc-url https://lasna-rpc.rnk.dev/ \
  --private-key $PRIVATE_KEY --chain-id 5318007 --value 0.01ether \
  --verify --verifier sourcify \
  src/MyContract.sol:MyContract --constructor-args $ARG1 $ARG2 $ARG3

# verify afterwards:
forge verify-contract --verifier sourcify --chain-id 5318007 $CONTRACT_ADDR $CONTRACT_NAME
```

Note: `--value` on deployment only works if the constructor is `payable` — the base
contracts' constructors are NOT payable, so add `payable` to your own constructor
(as in the minimal example) or fund afterwards via plain transfer / `depositTo()`.

## 7. CRON events (scheduled execution, no external trigger)

The legacy system contract `0x0000000000000000000000000000000000fffFfF` emits `Cron`
events at fixed block intervals; subscribe with `chainId = block.chainid` and
`contract = LEGACY_SYSTEM_ADDR`:

| Event | Interval | ~Time | topic0 |
|---|---|---|---|
| Cron1 | every block | ~1s | `0xf02d6ea5c22a71cffe930a4523fcb4f129be6c804db50e4202fb4e0b07ccb514` |
| Cron10 | 10 blocks | ~10s | `0x04463f7c1651e6b9774d7f85c85bb94654e3c46ca79b0c16fb16d4183307b687` |
| Cron100 | 100 blocks | ~2 min | `0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70` |
| Cron1000 | 1000 blocks | ~17 min | `0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4` |
| Cron10000 | 10000 blocks | ~3h | `0xd214e1d84db704ed42d37f538ea9bf71e44ba28bc1cc088b2f5deca654677a56` |

- Each Cron event carries one non-indexed `uint256 number` (the block) in `log_.data`;
  usually just read `block.number` instead.
- Overlapping subscriptions double-bill (Cron1 + Cron10 = 2 reactive txs every 10th
  block). CRON bills on EVERY tick even if `react()` does nothing — pick the longest
  interval that fits and provide an unsubscribe off-switch.
- A callback can target Reactive itself (`chainId: block.chainid`,
  `recipient: address(this)`) to run work in a fresh tx rather than inside `react()`.

## 8. Economy & gotchas (read before building)

Source: https://dev.reactive.network/economy — this is the most important page after
the contract guides.

- **Three balances**: contract balance (its own funds) vs **reserves** (pre-paid fee
  credit held by system contract/proxy) vs **debt** (fees owed). Charges consume
  reserves first, then accrue debt. Deposits clear debt first, then add reserves.
- **ANY debt blocks execution.** System contract won't call `react()` and the proxy
  won't deliver callbacks while debt > 0. An indebted contract goes quiet (no loud
  failure). Status flips via `BlacklistContract` / `WhitelistContract` events;
  check status on Reactscan.
- **Reverting react() is still billed in full** (caught, logged as
  `ReactiveContractReverted`, charged). Same for failing callbacks (`CallbackFailure`).
  Never use revert as a filter — non-matching logs should fall through silently.
  A contract reverting on every notification still drains its funds.
- **Fee formula**: `fee = p_base * C * (g_used + K)` where C = coefficient
  (`_gasPriceCoeffPer1000`/1000, default 1000 → C=1 on Reactive), K = surcharge
  (`_extraGas`, default 100,000 gas). Query live values with cast, don't rely on
  defaults. Fees go to the validator that posted the tx (tx.origin kickback).
- **Gas limits**: reactive tx max **900,000 gas**. Callback minimum gas limit
  **100,000** (requests below are ignored). Not all requested callback gas reaches
  the target — the proxy withholds `_extraGas` + `_maxChargeGas` for its own
  accounting/payment; too little left ⇒ `InsufficientGas` failure. Size limits
  generously (docs example uses 1,000,000).
- **Funding routes**: `depositTo(address)` on the system contract (Reactive side)
  or callback proxy (destination side) — settles debt first, then reserves; works
  without the target contract's cooperation (also the way to revive a stalled
  third-party contract). Direct transfers raise balance only — they do NOT settle
  debt or create reserves. `AbstractPayer.pay()` auto-settles shortfall inside the
  charge tx (capped at `_maxChargeGas`); expose `coverDebt()` (wrapping internal
  `_coverDebt()`) if manual settlement should be possible.
- **Never send REACT directly to the system contract** to fund a contract — it
  credits the sender's own address, not the contract. Always use `depositTo(target)`.
- **Funds sent to an indebted contract can be stranded** if it exposes no
  `coverDebt()` — the balance can't be applied to debt by anyone. Use `depositTo()`
  when unsure.
- **Callback billing lands on the recipient** in the destination chain's native
  token. A callback to an address with no code is rejected before any charge
  (the only free failure).
- **Callbacks are inspected via** `getCallbacks(txHash)` on the system contract —
  returns array of (block, requester, index, dest chainId, dest tx hash, err);
  empty array = not yet recorded, not necessarily failed.
- **Reactscan has no programmatic verification API** (per a builder runbook) — use
  Sourcify verification via forge as in §6.
- **Subscriptions are node-side, unreadable on-chain** — track them in your own
  contract storage if logic depends on them.

## 9. Official links

- Docs: https://dev.reactive.network/ (Getting Started)
  - Reactive Contracts: https://dev.reactive.network/reactive-contracts
  - Callback Contracts: https://dev.reactive.network/callback-contracts
  - Origins & Destinations: https://dev.reactive.network/origins-and-destinations
  - Economy & System Interactions: https://dev.reactive.network/economy
  - Mainnet / Lasna Testnet: https://dev.reactive.network/reactive-mainnet
  - Demos (legacy): https://dev.reactive.network/legacy/demos
  - Reactscan guide: https://dev.reactive.network/reactscan
- Website: https://reactive.network/ — Blog: https://blog.reactive.network/
- GitHub org: https://github.com/Reactive-Network
  - reactive-lib-omni (current Omni base lib): https://github.com/Reactive-Network/reactive-lib-omni
    (only 2 commits, empty README as of 19 Nov 2026 — brand new)
  - reactive-smart-contract-demos (demos; legacy-era): https://github.com/Reactive-Network/reactive-smart-contract-demos
  - Also: reactive-lib (legacy), system-smart-contracts, hackathon, reactive-bounties,
    kopli-faucet. Roadmap says repos will move to a `reactive-network/` org with
    Apache 2.0/MIT licensing (announced, in progress).
- X: https://twitter.com/0xReactive
- Telegram: t.me/Reactive_Network (community), t.me/parsiq_group (community chat),
  t.me/reactivedevs (developer channel, from 2024 hackathon materials)
- Discord: discord.gg/PMWaxp5dFp (community, per BTCC listing), discord.gg/bPNAjTS2ax
  (developer, from 2024 hackathon materials), discord.com/invite/SaZAfkgZhj (per
  CoinCarp listing) — multiple invites found; verify which is live before sharing.
- Staking portal: https://portal.reactive.network
- Demos to study (all on the legacy demos page; adapt patterns to Omni):
  Basic Demo, Uniswap V2 Stop Order, Stop-Loss & Take-Profit, Aave Liquidation
  Protection, Leverage Loop, Automated Prediction Market, Gasless Cross-Chain Atomic
  Swap, Approval Magic, Hyperlane, CRON.
- VS Code extension: "Reactive Network Assistant" (snippets/templates for RSCs).
- No-code alternative: Reactor (blog.reactive.network/reactor-...) — template-driven
  RSC deployment; NOT what a hackathon build should use (judges want code).

## 10. Hackathon build implications (for the parent agent)

- The event is literally named "Omni" — judges will expect the Omni model
  (`AbstractReactive` + `requestCallbackV_1_0`), not legacy RVM code.
- Testnet demo loop that works TODAY on Lasna: origin = Sepolia / Base Sepolia /
  Unichain Sepolia / Lasna itself; destination = same set. A Lasna→Lasna loop
  (react to a Lasna event, callback to a Lasna contract) is the simplest provable
  demo; a Sepolia→Lasna→Sepolia loop is the strongest cross-chain story but needs
  Sepolia ETH for the callback contract's funding too.
- Funding needed before building: Sepolia ETH (free faucets) → lREACT via the
  faucet contract (§4). Both sides must be funded: RSC in lREACT, callback contract
  in destination native token.
- REACT token price is tiny (~$0.002, ~$670k market cap per CoinCodex 19 Nov 2026)
  — the $5,500 prize in REACT is ~2.5M REACT at that price; thin liquidity is a
  real cash-out consideration, but that does not affect the build.
- Competing reference builds exist on GitHub (react.fun multi-chain launchpad,
  the-fixer-hook, lambda-protocol, rn-wallet-guardian) — good for patterns, but the
  submission must be original work.
- Suggested build angles fitting the tracks (verify tracks on the DoraHacks event
  page before committing): cross-chain stop-loss / liquidation protection, automated
  prediction-market payouts, CRON-based DCA / recurring payments, wallet-guardian
  (drain protection), one-step cross-chain swap.

## 11. To verify on-chain before building (not yet checked)

- Lasna RPC liveness + current block (eth_chainId should return 5318007).
- `forge install Reactive-Network/reactive-lib-omni` works and the `@reactive/`
  remapping resolves (repo is 2 commits young — check it actually contains
  src/base/{AbstractReactive,AbstractCallback,AbstractPayer}.sol and
  src/interfaces/{ISystemContract,IReactive,IPayable}.sol).
- Faucet contract `request(address)` behavior on Sepolia (whether plain ETH
  transfer also credits, and how long lREACT takes to land on Lasna).
- Whether Reactscan Lasna shows subscriptions/debt status for a deployed RSC.
