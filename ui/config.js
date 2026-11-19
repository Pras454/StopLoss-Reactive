// StopLoss — network + contract configuration (Reactive Omni Buildathon, Track 1).
//
// All addresses verified on-chain 19 Nov 2026 (see ../BUILD.md and ../DEMO.md).
// Both contracts are Sourcify-verified. The reactive contract (Lasna) and the
// vault (Base Sepolia) share the same address — same deployer, same nonce 0 —
// on different chains. Testnet only, no real funds.
window.STOPLOSS_CONFIG = {
  baseSepolia: {
    chainId: 84532,
    chainIdHex: "0x14a34",
    name: "Base Sepolia",
    rpcUrl: "https://sepolia.base.org",
    explorerUrl: "https://sepolia.basescan.org",
    nativeCurrency: { name: "Sepolia ETH", symbol: "ETH", decimals: 18 },
  },
  lasna: {
    chainId: 5318007,
    chainIdHex: "0x512577",
    name: "Reactive Lasna Testnet",
    rpcUrl: "https://lasna-rpc.rnk.dev/",
    explorerUrl: "https://lasna.reactscan.net",
    nativeCurrency: { name: "lREACT", symbol: "lREACT", decimals: 18 },
  },
  contracts: {
    // StopLossVault on Base Sepolia — deployed 19 Nov 2026, Sourcify-verified.
    vault: "0xcfc07ac67a31f72bca520a999d701a14642bd01c",
    // StopLossReactive on Lasna — deployed 19 Nov 2026, Sourcify-verified.
    reactive: "0xcFc07ac67a31f72BCA520a999D701A14642Bd01C",
    // Uniswap V3 WETH/USDC pool, fee 3000, on Base Sepolia.
    // token0 = USDC (6 dec), token1 = WETH (18 dec).
    pool: "0x46880b404CD35c165EDdefF7421019F8dD25F4Ad",
    weth: "0x4200000000000000000000000000000000000006",
    usdc: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
    // Base Sepolia callback proxy (Reactive Network).
    callbackProxy: "0x476F44b11F5C942c58f4c8E3d0300E5710743585",
  },
  usdcDecimals: 6,
  abis: {
    // Minimal fragments — only the functions the UI calls.
    vault: [
      "function depositWETH(uint256 amount)",
      "function withdrawWETH(uint256 amount)",
      "function createOrder(uint256 amountWeth, uint160 stopThreshold) returns (uint256 orderId)",
      "function cancelOrder(uint256 orderId)",
      // orders() returns a single struct — the tuple form is required.
      "function orders(uint256 id) view returns (tuple(address owner, uint256 amountWeth, uint160 stopThreshold, bool active))",
      "function nextOrderId() view returns (uint256)",
      "function balances(address user) view returns (uint256)",
      "function currentSqrtPriceX96() view returns (uint160)",
    ],
    // Reactive contract: read-only from the UI. Arming is an owner step done
    // from the deployer (see ../DEMO.md) — the UI never writes to Lasna.
    reactive: [
      "function armed() view returns (bool)",
      "function stopThreshold() view returns (uint160)",
      "function armedOrderId() view returns (uint256)",
      "function vault() view returns (address)",
      "function owner() view returns (address)",
    ],
    erc20: [
      "function approve(address spender, uint256 amount) returns (bool)",
      "function allowance(address owner, address spender) view returns (uint256)",
      "function balanceOf(address account) view returns (uint256)",
      "function decimals() view returns (uint8)",
      "function symbol() view returns (string)",
    ],
    weth: [
      "function deposit() payable",
      "function withdraw(uint256 amount)",
      "function balanceOf(address account) view returns (uint256)",
      "function allowance(address owner, address spender) view returns (uint256)",
      "function approve(address spender, uint256 amount) returns (bool)",
    ],
  },
};
