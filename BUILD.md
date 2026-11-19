# StopLoss — Track 1 build (Reactive Omni Buildathon)

Reactive stop-loss on the **real Uniswap V3 WETH/USDC pool on Base Sepolia**.
A user deposits WETH into a vault with a stop price; a reactive contract on
Lasna watches the pool's Swap events and — the moment a swap pushes the price
below the stop — triggers a callback that sells the vaulted WETH for USDC and
pays the user. No oracle, no off-chain bot: the reactive contract itself
catches the moment (Track 1 requirement).

Deadline: **6 Dec 2026 03:00 WIB**. Prize: $5,500 in REACT (Track 1: 1st
$2,000 + runner-up $250).

## Architecture

```
Base Sepolia (84532)                          Lasna (5318007)
┌────────────────────────────┐      Swap event      ┌──────────────────────────┐
│ Uniswap V3 pool            │ ── Swap log ────────▶ │ StopLossReactive         │
│ WETH/USDC 0.3%             │  (sqrtPriceX96 in    │ - subscribes to Swap on  │
│ 0x46880b40…25F4Ad          │   log data, 3rd word)│   the pool               │
└────────────┬───────────────┘                      │ - armed stop: threshold  │
             │ swap()                               │   + orderId              │
             ▼                                      │ - price < stop ⇒        │
┌────────────────────────────┐      callback        │   requestCallbackV_1_0   │
│ StopLossVault              │ ◀─────────────────── │   (gas 1,000,000)        │
│ - depositWETH / withdraw   │  via Base Sepolia    └──────────────────────────┘
│ - createOrder / cancel     │  callback proxy
│ - executeStopLoss (proxy   │  0x476F44b1…43585
│   + reactive auth)         │
│ - uniswapV3SwapCallback    │  User flow: deposit WETH → createOrder(amount,
│   (pays WETH owed)         │  threshold) → operator arms RSC → trigger sells
└────────────────────────────┘  WETH → USDC → user.
```

Contracts: `src/StopLossReactive.sol` (AbstractReactive, Omni model),
`src/StopLossVault.sol` (AbstractCallback), interfaces in
`src/interfaces/` (IERC20, IWETH, IUniswapV3Pool, TickMath).
Tests: `test/StopLoss.t.sol` (17 tests + mocks). Deploy scripts:
`script/DeployReactive.s.sol`, `script/DeployVault.s.sol`.

## Addresses & parameters (verified on-chain 19 Nov 2026)

| Item | Value |
|---|---|
| Base Sepolia chain / RPC | 84532 / https://sepolia.base.org |
| Lasna chain / RPC | 5318007 / https://lasna-rpc.rnk.dev/ |
| Uniswap V3 pool WETH/USDC 0.3% | 0x46880b404CD35c165EDdefF7421019F8dD25F4Ad |
| token0 USDC (6 dec) | 0x036CbD53842c5426634e7929541eC2318f3dCF7e |
| token1 WETH (18 dec) | 0x4200000000000000000000000000000000000006 |
| Swap topic0 | 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67 |
| Base Sepolia callback proxy | 0x476F44b11F5C942c58f4c8E3d0300E5710743585 |
| Lasna system contract | 0x8888888888888888888888888888888888888888 |
| Pool state at research time | tick 174308, sqrtPriceX96 ≈ 4.8278e32, liquidity ≈ 3.13e14, ≈ $26,932/WETH |
| Callback gas limit | 1,000,000 |
| Deployer (testnet only) | 0xD341B8a2bEc4244Df9865EC0e9136F151640D01F |

## ⚠️ Two spec corrections (both verified, both would have broken the demo)

1. **Trigger comparison is `>`, not `<`.** In this pool sqrtPriceX96² = y/x
   (token1 per token0, raw), so the WETH price in USDC is
   `10^12 / (sqrtPriceX96/2^96)²` — WETH price and sqrtPriceX96 move in
   OPPOSITE directions. WETH falling ⟺ sqrtPriceX96 RISING. The stop
   threshold is therefore a sqrtPriceX96 value ABOVE the current sqrtPriceX96
   and the trigger fires on `sqrtPriceX96 > threshold`. Verified two ways:
   the pool's live tick 174308 reproduces its sqrtPriceX96 exactly, and the
   formula reproduces the known mainnet USDC/WETH price (~$3,000 at
   sqrtPriceX96 ≈ 1.45e33). With `<` the contract would have been a
   take-profit (triggering on price rises) and the demo's WETH sell would
   never have triggered it.
2. **`sqrtPriceLimitX96` for the vault's sell is `MAX_SQRT_RATIO - 1`, not
   `MIN_SQRT_RATIO + 1`.** The sell is token1→token0 (`zeroForOne = false`),
   for which the limit is a CEILING that must sit above the current price;
   the minimum value would make every swap revert.

Also: the pool address checksum is
`0x46880b404CD35c165EDdefF7421019F8dD25F4Ad` (the brief's all-lowercase form
fails solc's checksum check — same address, correct EIP-55 casing).

## Threshold math (for the demo)

- WETH price from the pool: `priceUsd = 10^12 / (sqrtPriceX96 / 2^96)²`
  (read live via `vault.currentSqrtPriceX96()` or `pool.slot0()`).
- Threshold from a target stop price: `threshold = 2^96 * sqrt(10^12 / priceUsd)`.
- Example at research-time price ($26,932): a stop 0.5% below ($26,797) ⇒
  threshold ≈ 4.8399e32 (vs current 4.8278e32).
- Price impact: at active liquidity L ≈ 3.13e14, selling Δy WETH moves
  √P by Δy/L. Selling **0.01 WETH moves the price ≈ 1%** — so a 0.5% stop
  plus a 0.01 WETH sell crosses it with margin. (If pool liquidity changes,
  re-measure with `pool.liquidity()` before the demo.)

## Demo run (full loop, all on-chain)

1. Deploy RSC on Lasna, vault on Base Sepolia (order below), set vault in RSC.
2. Fund: RSC with lREACT (deploy script sends 1), vault with Base Sepolia ETH
   (deploy script sends 0.01; top up via `depositTo` on the proxy if needed).
3. Deployer wraps 0.005 Base Sepolia ETH → WETH, approves vault, deposits,
   creates order 0 with stop threshold (0.5% below live price, computed above).
4. Operator arms the RSC: `arm(0, threshold)` on Lasna.
5. Deployer sells 0.01 WETH into the pool (direct `pool.swap`, zeroForOne
   false) — this is the "market crash" that pushes the price below the stop.
6. The Swap log's sqrtPriceX96 crosses the threshold → RSC `react()` fires →
   `StopTriggered` + `CallbackRequested` on Lasna → callback lands on Base
   Sepolia → vault sells the 0.005 WETH → USDC to the deployer
   (`StopLossExecuted`). Collect all tx hashes for the submission.
7. Verify on Reactscan (Lasna) + Base Sepolia explorer: reactive tx,
   callback tx, vault swap tx, USDC transfer to the user.

## Build & test

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge build   # Solc 0.8.36 — "Compiler run successful!", ZERO warnings
forge test    # 19 passed, 0 failed (17 StopLoss + 2 Counter)
```

Test coverage: threshold logic (above triggers / below + equal do not),
`react()` silently ignores non-Swap logs (wrong topic/chain/contract/opCode/
short data) and reverts for non-system callers, constructor subscribes once,
owner setters + arm/disarm, `coverDebt()` pays the system contract and the
callback proxy, vault order lifecycle (deposit → order → callback execution
→ user receives USDC at the mock rate), `executeStopLoss` reverts for
non-proxy callers and wrong reactive addresses, `uniswapV3SwapCallback`
reverts for non-pool callers, order cancel returns WETH.

Deploy scripts were validated end-to-end against a local anvil chain
(reactive + vault both deployed and logged addresses). Note: a bare anvil
has no code at the system address, so the constructor's `subscribe()` call
reverts there — the mock system bytecode was etched at 0x8888…8888 for the
local test. On Lasna the real system contract is live, so this is a
local-only quirk.

## Remaining work (parent)

1. **Bridge more Base Sepolia ETH (recommended).** 0.01 SepETH was bridged
   19 Nov ~10:04 WIB (deposit pending at last check). Comfortable demo
   budget ≈ 0.02 Base Sepolia ETH total: 0.005 vault deposit + 0.01
   price-moving sell + ~0.005 gas/callback funding. ~0.014 Sepolia ETH
   remains on Ethereum Sepolia for a second bridge if needed.
2. **Deploy** (in order): (a) `DeployReactive.s.sol` on Lasna — needs
   `PRIVATE_KEY` env; (b) `DeployVault.s.sol` on Base Sepolia — needs
   `PRIVATE_KEY` + `REACTIVE_ADDR` env; (c) `setVault(vault)` on the RSC;
   (d) verify both on Sourcify (`forge verify-contract --verifier sourcify`).
3. **Fund reserves**: if either contract accrues debt, use `depositTo()` on
   the system contract (Lasna) / callback proxy (Base Sepolia), or call the
   contracts' `coverDebt()`. Check debt status on Reactscan before the demo.
4. **Run the demo** (section above) and record every tx hash + explorer links.
5. **UI + video + repo**: minimal UI (deposit / create order / live status),
   demo video < 3 min, public GitHub repo (Bagus creates the empty repo —
   the token cannot), DoraHacks submission before 6 Dec 2026 03:00 WIB.
6. **Known limits**: one armed stop at a time per RSC (by design — one
   trigger per order); arming is a manual operator step after order creation
   (the vault cannot call across chains to Lasna). The RSC owner is the
   deployer; no multi-user arming. Testnet pool price is stale/thin — the
   demo uses a tight relative stop, which is the honest way to demo it.
