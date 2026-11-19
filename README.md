# StopLoss Reactive — Reactive Omni Buildathon (Track 1: Every Second Counts)

An on-chain stop-loss for WETH on Base Sepolia, triggered by a Reactive Smart
Contract (RSC) on the Reactive Lasna testnet. When the Uniswap V3 WETH/USDC
pool price drops past a user's stop, the RSC catches the Swap event and fires a
callback that sells the user's WETH for USDC — no keeper, no off-chain bot.

DoraHacks event: Reactive Omni Buildathon — Track 1 "Every Second Counts".
Deadline: 6 Dec 2026, 03:00 WIB.

## How it works

1. User wraps ETH, deposits WETH into `StopLossVault` (Base Sepolia) and
   creates a stop-loss order (amount + stop price).
2. The owner arms `StopLossReactive` (Lasna) with the order's sqrtPriceX96
   threshold. The RSC subscribes to `Swap` events on the WETH/USDC pool.
3. A sell pushes the pool price below the stop. The RSC's `react()` sees the
   Swap log, checks the threshold, and requests a callback.
4. The callback contract (`StopLossVault`) sells the order's WETH through the
   pool directly (`pool.swap()`, no router exists on Base Sepolia) and sends
   the USDC to the user.

Note: in this pool WETH is token1 and USDC is token0, so a falling WETH price
means a *rising* sqrtPriceX96 — the trigger is `sqrtPriceX96 > threshold`.

## Deployed contracts (testnet)

| Contract | Chain | Address |
| --- | --- | --- |
| StopLossReactive | Lasna (5318007) | 0xcFc07ac67a31f72BCA520a999D701A14642Bd01C |
| StopLossVault | Base Sepolia (84532) | 0xcfc07ac67a31f72bca520a999d701a14642bd01c |
| Uniswap V3 WETH/USDC pool (fee 3000) | Base Sepolia | 0x46880b404CD35c165EDdefF7421019F8dD25F4Ad |

Both contracts are source-verified on Sourcify. The RSC and the vault share an
address (same deployer + nonce 0 on both chains) — coincidence, not a bug.

## Live demo (verified on-chain, 19 Nov 2026)

Full record: [DEMO.md](DEMO.md). Video: `demo-video/stoploss-demo.mp4` (2:03).

- Order #0: 0.003 WETH, stop −0.5% from $26,930.98.
- Trigger sell of 0.008 WETH pushed the price to $26,624.35 (−1.14%):
  `0xcdf7c2573ce0751b1cac26b80a2143948a4545b2fb5c9e03439992c69b33cbb9`
- Reactive tx on Lasna (from the validator, not the deployer):
  `0xb82dff8d21be41405285f5a575fde3a4a6e081f5b3c3d9c6bc5b7c8a99f1928c`
- Callback tx on Base Sepolia (~20 s later) — vault sold 0.003 WETH for
  **79.757622 USDC**:
  `0x92c19a29203ad48b714d427b90ba99f5ca7f4794f1f54e449fd1725c0d53ce16`

## Repo layout

- `src/StopLossReactive.sol` — the RSC (AbstractReactive, Omni model).
- `src/StopLossVault.sol` — the callback contract (AbstractCallback) + vault.
- `src/Swapper.sol` — demo-only helper that sells WETH to move the price.
- `src/interfaces/` — minimal IERC20 / IWETH / IUniswapV3Pool / TickMath.
- `test/StopLoss.t.sol` — 19 tests (17 StopLoss + 2 Counter), all passing.
- `script/DeployReactive.s.sol`, `script/DeployVault.s.sol` — deploy scripts.
- `ui/` — browser UI (MetaMask, Base Sepolia): live price, wrap/deposit/
  withdraw, create/cancel orders. Run with `python3 -m http.server` in `ui/`.
- `demo-video/` — demo video + narration script + build scripts.
- `RESEARCH.md` — Reactive Omni model notes (subscriptions, callbacks,
  funding, gotchas). `BUILD.md` — build log.

## Build & test

```shell
forge build
forge test   # 19/19 pass
```

Requires Foundry. The reactive library is `Reactive-Network/reactive-lib-omni`
(v0.1.0) under `lib/`, remapped as `@reactive/`.

## Links

- Reactive docs: https://dev.reactive.network
- Lasna explorer: https://lasna.reactscan.net/
- Base Sepolia explorer: https://sepolia.basescan.org
