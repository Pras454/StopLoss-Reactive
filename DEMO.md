# StopLoss — Live demo record (19 Nov 2026, Track 1)

Full reactive loop executed end-to-end on testnet and verified on-chain.
All amounts are testnet tokens (no real value).

## Contracts (both Sourcify-verified)

| Contract | Chain | Address | Deploy tx |
|---|---|---|---|
| StopLossReactive | Lasna 5318007 | 0xcFc07ac67a31f72BCA520a999D701A14642Bd01C | 0x186f44f9218490ad68f2b3fd95961820cecc69fa85d4503deea9326c95b59b37 |
| StopLossVault | Base Sepolia 84532 | 0xcfc07ac67a31f72bca520a999d701a14642bd01c | 0x4232a3a5aeb3c293912aeba8b2a3619864ea2c70200a12848be01a9b1a88290b |
| Swapper (demo helper) | Base Sepolia 84532 | 0x0f79af0Bd6A6B8De78514E844C2A4B8dC1345C09 | 0xfd8549a0e1a1c866a46d61d404074c2476953283e0d4e52675f7394e4127a0c3 |

Note: RSC and vault share the same address on different chains (same deployer,
same nonce 0). setVault tx (Lasna): 0xd81c064d13895863d4e9f4beefda156f5d81a164779369bf3dce9276f0928b78.

Pool: Uniswap V3 WETH/USDC 0.3% on Base Sepolia, 0x46880b404CD35c165EDdefF7421019F8dD25F4Ad.

## Demo run — order #0 (19 Nov 2026 ~10:26–10:28 WIB)

Setup (all status 0x1):
1. Wrap 0.003 ETH → WETH: 0x349e1726c969fcefa0888a9558e1a9e031b45bcada86ee2286c0acf754d2f5bb
2. Approve vault: 0x8a58f572449a13bfab0be2aeeedd46f41a572f99edc0f8f1be12b9264c8001c5
3. depositWETH(0.003): 0xaae8848e9bc0c47627acdeb01fad9ec3c6bb2707768f519ea0ed691edae2208a
4. createOrder(0.003 WETH, threshold 483996212677633068168392311046144): 0x25cfd312e1baa02a1b28671a7ff5e08209197ef579c3873ca1fc7b0a77d2807f
5. arm(0, threshold) on Lasna: 0x08fd108b07b89cf39c413f7b696c1a33e5134dd8de5468919bee77fd98d6739f

Stop: 0.5% below the live pool price ($26,930.98 → stop $26,796.33).

Trigger — the "market crash":
6. Swapper.wrapAndSell (sold 0.008 WETH into the pool): 0xcdf7c2573ce0751b1cac26b80a2143948a4545b2fb5c9e03439992c69b33cbb9 (Base Sepolia block 60684777, status 0x1)
   Pool price moved $26,930.98 → $26,624.35 (-1.14%); sqrtPriceX96 482784705864696079139330109463482 → 485556823244476549274259834240440, crossing the threshold.

Reactive execution (by the network itself, not the deployer):
7. Reactive tx on Lasna (StopTriggered + CallbackRequested): 0xb82dff8d21be41405285f5a575fde3a4a6e081f5b3c3d9c6bc5b7c8a99f1928c (block 8702783, status 0x1, gas 97,561, from validator 0x038e06667e42782e571eab20432b9237f9bd6b82)

Callback execution:
8. Callback tx on Base Sepolia (StopLossExecuted): 0x92c19a29203ad48b714d427b90ba99f5ca7f4794f1f54e449fd1725c0d53ce16 (block 60684787 — 10 blocks / ~20s after the sell)
   Vault sold 0.003 WETH → **79.757622 USDC** paid to the order owner (deployer balance confirmed on-chain).

Post-demo checks: RSC debt 0, vault debt 0, RSC armed=false, order #0 active=false.

## Explorer links
- Reactive tx: https://lasna.reactscan.net/tx/0xb82dff8d21be41405285f5a575fde3a4a6e081f5b3c3d9c6bc5b7c8a99f1928c
- Callback tx: https://sepolia.basescan.org/tx/0x92c19a29203ad48b714d427b90ba99f5ca7f4794f1f54e449fd1725c0d53ce16
- Sell tx: https://sepolia.basescan.org/tx/0xcdf7c2573ce0751b1cac26b80a2143948a4545b2fb5c9e03439992c69b33cbb9
- RSC: https://lasna.reactscan.net/address/0xcFc07ac67a31f72BCA520a999D701A14642Bd01C
- Vault: https://sepolia.basescan.org/address/0xcfc07ac67a31f72bca520a999d701a14642bd01c
