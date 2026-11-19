#!/usr/bin/env python3
"""Render the StopLoss demo-video slides (1280x720 PNGs) with PIL.

No browser needed. Real data only: every address, tx hash, block number and
figure is copied from ~/workspace/dorahacks-reactive/DEMO.md (verified
on-chain 19 Nov 2026). No private keys anywhere.
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 720
OUT = "/home/hatch/workspace/dorahacks-reactive/demo-video/slides"

BG = (10, 15, 30)
PANEL = (17, 25, 46)
PANEL2 = (23, 33, 60)
WHITE = (241, 245, 249)
MUTED = (148, 163, 184)
CYAN = (34, 211, 238)
GREEN = (52, 211, 153)
AMBER = (245, 158, 11)
RED = (248, 113, 113)
BORDER = (51, 65, 85)

F = "/usr/share/fonts/truetype/dejavu/"


def font(name, size):
    return ImageFont.truetype(F + name, size)


BOLD = lambda s: font("DejaVuSans-Bold.ttf", s)
REG = lambda s: font("DejaVuSans.ttf", s)
MONO = lambda s: font("DejaVuSansMono.ttf", s)
MONOB = lambda s: font("DejaVuSansMono-Bold.ttf", s)


def canvas():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 6], fill=CYAN)
    return img, d


def center(d, y, text, f, fill=WHITE):
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2, y), text, font=f, fill=fill)
    return w


def label(d, text, x=80, y=56):
    d.text((x, y), text, font=BOLD(24), fill=CYAN)


def footer(d, text="StopLoss  •  Reactive Omni Buildathon, Track 1  •  testnet tokens only"):
    d.text((80, H - 44), text, font=REG(18), fill=MUTED)


def card(d, box, fill=PANEL, outline=BORDER):
    d.rounded_rectangle(box, radius=16, fill=fill, outline=outline, width=2)


def save(img, name):
    img.save(f"{OUT}/{name}")
    print("wrote", name)


# ---------------------------------------------------------------- 1. title
img, d = canvas()
center(d, 200, "StopLoss", BOLD(96))
center(d, 320, "A stop-loss that catches the moment itself", REG(34), MUTED)
d.line([440, 410, 840, 410], fill=BORDER, width=2)
center(d, 440, "Reactive Smart Contract on Lasna  •  Uniswap V3 on Base Sepolia", BOLD(25), CYAN)
center(d, 500, "No oracle. No keeper. No off-chain bot.", REG(24), MUTED)
center(d, 560, "Reactive Omni Buildathon — Track 1: Every Second Counts", REG(22), AMBER)
save(img, "01_title.png")

# --------------------------------------------------------------- 2. problem
img, d = canvas()
label(d, "THE PROBLEM")
d.text((80, 110), "Stop-losses protect you —", font=BOLD(50), fill=WHITE)
d.text((80, 175), "if something is watching.", font=BOLD(50), fill=CYAN)
card(d, [80, 300, 600, 470], fill=(60, 20, 24), outline=(120, 40, 40))
d.text((110, 330), "A bot or server watches", font=BOLD(26), fill=WHITE)
for i, t in enumerate(["Servers crash. Bots lag.", "Seconds cost real money."]):
    d.text((110, 380 + i * 38), t, font=REG(23), fill=(252, 165, 165))
card(d, [680, 300, 1200, 470], fill=(60, 20, 24), outline=(120, 40, 40))
d.text((710, 330), "You watch the chart", font=BOLD(26), fill=WHITE)
for i, t in enumerate(["You sleep. You blink.", "The crash does not wait."]):
    d.text((710, 380 + i * 38), t, font=REG(23), fill=(252, 165, 165))
d.text((80, 540), "What if the chain itself watched the price?", font=BOLD(28), fill=WHITE)
footer(d)
save(img, "02_problem.png")

# ---------------------------------------------------------- 3. architecture
img, d = canvas()
label(d, "THE SOLUTION  —  HOW IT WORKS")
# top-left: pool
card(d, [80, 110, 580, 300])
d.text((105, 130), "BASE SEPOLIA", font=BOLD(20), fill=AMBER)
d.text((105, 165), "Uniswap V3 pool", font=BOLD(28), fill=WHITE)
d.text((105, 210), "WETH / USDC  •  0.3% fee", font=REG(22), fill=MUTED)
d.text((105, 250), "0x46880b40…25F4Ad", font=MONO(20), fill=CYAN)
# top-right: RSC
card(d, [700, 110, 1200, 300], fill=(16, 42, 54), outline=CYAN)
d.text((725, 130), "LASNA", font=BOLD(20), fill=AMBER)
d.text((725, 165), "StopLossReactive", font=BOLD(28), fill=WHITE)
d.text((725, 210), "Subscribes to Swap events", font=REG(22), fill=MUTED)
d.text((725, 250), "Price < stop  →  request callback", font=REG(22), fill=GREEN)
# arrow pool -> RSC
d.text((595, 185), ">>>", font=BOLD(30), fill=AMBER)
d.text((480, 310), "Swap log carries the new price", font=REG(20), fill=MUTED)
# bottom: vault
card(d, [380, 420, 900, 600])
d.text((405, 440), "BASE SEPOLIA", font=BOLD(20), fill=AMBER)
d.text((405, 475), "StopLossVault", font=BOLD(28), fill=WHITE)
d.text((405, 520), "Sells vaulted WETH → USDC, pays the user", font=REG(22), fill=MUTED)
d.text((405, 555), "0xcfc07ac6…42bd01c", font=MONO(20), fill=CYAN)
# arrow RSC -> vault
d.text((985, 345), "callback", font=BOLD(22), fill=AMBER)
d.text((985, 375), "via proxy", font=REG(20), fill=MUTED)
d.line([950, 300, 880, 420], fill=AMBER, width=4)
d.polygon([(880, 420), (868, 398), (894, 400)], fill=AMBER)
footer(d)
save(img, "03_architecture.png")

# ------------------------------------------------------------- 4. the order
img, d = canvas()
label(d, "LIVE DEMO  —  THE ORDER  (19 NOV 2026)")
d.text((80, 110), "Order #0: 0.003 WETH, stop 0.5% below market", font=BOLD(38), fill=WHITE)
card(d, [80, 190, 1200, 470])
rows = [
    ("Live pool price", "$26,930.98 / WETH"),
    ("Stop price", "$26,796.33  (−0.5%)"),
    ("Threshold (sqrtPriceX96)", "483996212677633068168392311046144"),
    ("Status", "Armed on Lasna"),
]
y = 220
for k, v in rows:
    d.text((110, y), k, font=REG(24), fill=MUTED)
    col = GREEN if v == "Armed on Lasna" else WHITE
    d.text((480, y), v, font=BOLD(24) if v == "Armed on Lasna" else MONO(24), fill=col)
    y += 58
d.text((80, 500), "Setup:  depositWETH  0xaae8…208a    createOrder  0x25cf…807f    arm (Lasna)  0x08fd…39f",
       font=MONO(19), fill=MUTED)
d.text((80, 545), "All setup transactions confirmed on-chain, status 0x1.", font=REG(22), fill=MUTED)
footer(d)
save(img, "04_order.png")

# -------------------------------------------------------------- 5. the crash
img, d = canvas()
label(d, "LIVE DEMO  —  THE CRASH")
d.text((80, 110), "A market sell hits the pool.", font=BOLD(44), fill=WHITE)
center(d, 210, "$26,930.98   →   $26,624.35", BOLD(54), WHITE)
center(d, 290, "−1.14%  —  straight through the stop", BOLD(32), RED)
card(d, [80, 380, 1200, 560])
d.text((110, 405), "Trigger sell: 0.008 WETH into the pool (Swapper)", font=REG(24), fill=WHITE)
d.text((110, 450), "sqrtPriceX96 crossed the stop threshold", font=REG(24), fill=WHITE)
d.text((110, 505), "Sell tx (Base Sepolia, block 60684777):", font=BOLD(20), fill=MUTED)
d.text((110, 530), "0xcdf7c2573ce0751b1cac26b80a2143948a4545b2fb5c9e03439992c69b33cbb9",
       font=MONO(17), fill=CYAN)
footer(d)
save(img, "05_crash.png")

# ------------------------------------------------------------ 6. reactive tx
img, d = canvas()
label(d, "THE NETWORK CATCHES IT  —  LASNA")
card(d, [80, 105, 1200, 600])
d.text((110, 130), "Reactive transaction", font=BOLD(22), fill=MUTED)
d.text((110, 162), "0xb82dff8d21be41405285f5a575fde3a4a6e081f5b3c3d9c6bc5b7c8a99f1928c",
       font=MONO(19), fill=CYAN)
rows = [
    ("Block", "8,702,783  (Lasna)"),
    ("Events", "StopTriggered + CallbackRequested"),
    ("Submitted by", "Network validator 0x038e…b82"),
    ("Gas used", "97,561"),
    ("Status", "Success"),
]
y = 225
for k, v in rows:
    d.text((110, y), k, font=REG(24), fill=MUTED)
    col = GREEN if v == "Success" else WHITE
    d.text((420, y), v, font=BOLD(24) if v == "Success" else MONO(24), fill=col)
    y += 52
d.text((110, 545), "Not submitted by us — proof the trigger is genuinely autonomous.",
       font=REG(22), fill=GREEN)
footer(d)
save(img, "06_reactive.png")

# ------------------------------------------------------------ 7. callback tx
img, d = canvas()
label(d, "THE CALLBACK LANDS  —  BASE SEPOLIA")
card(d, [80, 105, 1200, 600])
d.text((110, 130), "Callback transaction", font=BOLD(22), fill=MUTED)
d.text((110, 162), "0x92c19a29203ad48b714d427b90ba99f5ca7f4794f1f54e449fd1725c0d53ce16",
       font=MONO(19), fill=CYAN)
rows = [
    ("Block", "60,684,787  —  10 blocks (~20 s) after the sell"),
    ("Event", "StopLossExecuted"),
    ("Vault sold", "0.003 WETH"),
    ("Paid to owner", "79.757622 USDC"),
]
y = 225
for k, v in rows:
    d.text((110, y), k, font=REG(24), fill=MUTED)
    col = GREEN if v == "79.757622 USDC" else WHITE
    d.text((420, y), v, font=BOLD(24) if v == "79.757622 USDC" else MONO(24), fill=col)
    y += 52
d.text((110, 545), "USDC balance confirmed on-chain in the owner's wallet.",
       font=REG(22), fill=GREEN)
footer(d)
save(img, "07_callback.png")

# --------------------------------------------------------------- 8. trust
img, d = canvas()
label(d, "TRUST & PROOF")
d.text((80, 110), "Verified, tested, and settled clean.", font=BOLD(40), fill=WHITE)
card(d, [80, 190, 1200, 330])
d.text((110, 215), "✓  StopLossReactive  —  Sourcify-verified (Lasna)", font=BOLD(24), fill=GREEN)
d.text((110, 255), "0xcFc07ac67a31f72BCA520a999D701A14642Bd01C", font=MONO(21), fill=WHITE)
card(d, [80, 355, 1200, 495])
d.text((110, 380), "✓  StopLossVault  —  Sourcify-verified (Base Sepolia)", font=BOLD(24), fill=GREEN)
d.text((110, 420), "0xcfc07ac67a31f72bca520a999d701a14642bd01c", font=MONO(21), fill=WHITE)
d.text((110, 455), "Same address on both chains (same deployer, same nonce).", font=REG(20), fill=MUTED)
d.text((80, 535), "19 / 19 Foundry tests pass   •   Debt after demo: RSC 0, vault 0   •   Order #0 closed",
       font=BOLD(22), fill=CYAN)
footer(d)
save(img, "08_trust.png")

# ----------------------------------------------------------------- 9. close
img, d = canvas()
center(d, 120, "StopLoss", BOLD(64))
center(d, 210, "Your stop, caught by the chain itself.", REG(28), MUTED)
d.text((140, 300), "StopLossReactive (Lasna)", font=BOLD(22), fill=MUTED)
d.text((140, 330), "0xcFc07ac67a31f72BCA520a999D701A14642Bd01C", font=MONO(21), fill=WHITE)
d.text((140, 380), "StopLossVault (Base Sepolia)", font=BOLD(22), fill=MUTED)
d.text((140, 410), "0xcfc07ac67a31f72bca520a999d701a14642bd01c", font=MONO(21), fill=WHITE)
center(d, 490, "Reactive Omni Buildathon — Track 1: Every Second Counts", BOLD(26), CYAN)
center(d, 540, "Deadline 6 Dec 2026  •  $5,500 in REACT", REG(24), AMBER)
center(d, 600, "Base Sepolia + Lasna testnets  •  test tokens only",
       REG(22), MUTED)
save(img, "09_close.png")

print("done")
