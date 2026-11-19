# StopLoss — demo UI (Reactive Omni Buildathon, Track 1)

Minimal static web UI for the StopLoss demo. No build step, no backend, no
keys — MetaMask signs everything.

## What it does

- **Live panel** (works without a wallet): WETH price from the real Uniswap V3
  WETH/USDC pool on Base Sepolia (via `vault.currentSqrtPriceX96()`), plus the
  reactive contract's armed status, threshold, and armed order (read from Lasna
  via the public RPC). Auto-refreshes every 30 seconds.
- **Wrap** ETH → WETH on Base Sepolia.
- **Approve + deposit** WETH into the StopLossVault (exact-amount approval,
  never unlimited), and withdraw unallocated WETH.
- **Create stop-loss orders**: amount (WETH) + stop price (USD). The UI converts
  the stop price to the on-chain sqrtPriceX96 threshold in exact BigInt math
  and refuses a stop that is already crossed (stop must be below the live price).
- **Your orders**: the latest 10 on-chain orders filtered to the connected
  wallet, with a cancel button for active orders.
- Every action shows its transaction hash with a Basescan link.

Arming a stop is **not** in the UI: it is an owner step done from the deployer
on Lasna (`arm(orderId, threshold)`). See `../DEMO.md` for the full demo flow.

## Run it

```bash
cd ui
python3 -m http.server 8000
# open http://localhost:8000
```

Or just open `index.html` directly in a browser (file:// works — all chain
reads go to public RPCs). MetaMask must be on **Base Sepolia** (chain ID 84532);
the app adds/switches the network automatically on connect.

## Configuration

All addresses live in `config.js` (verified on-chain 19 Nov 2026):

| Item | Address |
|---|---|
| StopLossVault (Base Sepolia 84532) | `0xcfc07ac67a31f72bca520a999d701a14642bd01c` |
| StopLossReactive (Lasna 5318007) | `0xcFc07ac67a31f72BCA520a999D701A14642Bd01C` |
| Uniswap V3 pool WETH/USDC 0.3% | `0x46880b404CD35c165EDdefF7421019F8dD25F4Ad` |
| WETH (Base Sepolia) | `0x4200000000000000000000000000000000000006` |
| USDC (Base Sepolia) | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |

## Price math (direction matters)

In this pool, `priceUsd = 10^12 / (sqrtPriceX96 / 2^96)^2` — WETH falling means
sqrtPriceX96 **rising**, so the stop threshold sits above the current
sqrtPriceX96 and the reactive contract triggers on `sqrtPriceX96 > threshold`.
The UI's threshold conversion (`threshold = 2^96 * sqrt(10^12 / stopPrice)`)
uses exact BigInt integer-square-root math; verified by round-trip in Node
(stop $26,796.33 → threshold `483996170011468793289234383611378` →
back to $26,796.33, and the demo's live sqrtPriceX96 reproduces $26,930.98).
The demo's recorded threshold (`483996212677633068168392311046144`) differs
by only ~9e-8 relative — it was computed off-chain from a float-derived stop,
not from the exact decimal $26,796.33.
