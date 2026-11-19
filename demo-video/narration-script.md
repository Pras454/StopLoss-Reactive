# StopLoss — demo video narration script

English narration, single voice (Helio), ~370 words, ~2:00 at natural
pace. Recorded 19 Nov 2026 with `/opt/hatch/bin/tts` (one MP3 per section,
`audio/s1.mp3` … `audio/s5.mp3`), then concatenated for the video.

All facts come from `~/workspace/dorahacks-reactive/DEMO.md` (verified
on-chain 19 Nov 2026). Spoken forms are written as they should sound:
"0.003 WETH" as "three thousandths of a WETH", "79.757622" as
"seventy-nine point seven six". The on-screen slides carry the exact
figures, addresses and tx hashes.

## 1 — Problem (~15 s)

Stop-losses are supposed to protect you. But on-chain, they usually depend
on a bot, a server, or someone watching the chart. Servers crash. Bots lag.
And in a fast crash, seconds are the difference between selling at your stop
— and selling at the bottom.

## 2 — The solution (~35 s)

StopLoss removes the middleman. A Reactive Smart Contract on the Lasna
testnet watches the real Uniswap V3 WETH to USDC pool on Base Sepolia,
directly. Every swap in that pool emits a log carrying the new price — so
the contract reads the price from the log itself. No oracle. No keeper. No
off-chain bot. You deposit WETH into a vault and set your stop price. The
moment a swap pushes the price below your stop, the contract fires a
callback that sells your WETH for USDC.

## 3 — The demo: order + crash (~40 s)

Here it is, running live on testnet. Order zero: three thousandths of a WETH
in the vault, with a stop half a percent below the live price — twenty-six
thousand, seven hundred ninety-six dollars. Then the market moves. A sell of
eight thousandths of a WETH hits the pool and pushes the price down to
twenty-six thousand, six hundred twenty-four dollars — a drop of one point
one four percent, straight through the stop.

## 4 — Reactive + callback (~40 s)

The network itself catches it. A reactive transaction fires on Lasna — stop
triggered, callback requested — submitted by a network validator, not by us.
Ten blocks later, about twenty seconds, the callback lands on Base Sepolia,
and the vault sells. Three thousandths of a WETH becomes seventy-nine point
seven six USDC, paid straight to the order owner. Every step is verifiable
on the public explorers: the sell, the reactive transaction, and the
callback.

## 5 — Trust + close (~20 s)

Both contracts are deployed and source-verified, the full suite of nineteen
Foundry tests passes, and after the demo both contracts show zero debt.
StopLoss: your stop, caught by the chain itself. Built for the Reactive Omni
Buildathon — Track One: Every Second Counts.
