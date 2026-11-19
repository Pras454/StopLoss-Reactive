// StopLoss — UI logic (vanilla JS + ethers v6, no build step).
// Reads configuration from config.js (window.STOPLOSS_CONFIG).
// MetaMask signs everything; no keys anywhere in this UI.
//
// PRICE MATH (see ../BUILD.md — direction matters):
//   In this pool token0 = USDC (6 dec), token1 = WETH (18 dec), and
//   sqrtPriceX96^2 = y/x, so the WETH price in USDC is
//       priceUsd = 10^12 / (sqrtPriceX96 / 2^96)^2
//   WETH falling <=> sqrtPriceX96 RISING. A stop price therefore maps to a
//   sqrtPriceX96 threshold ABOVE the current value:
//       threshold = 2^96 * sqrt(10^12 / stopPriceUsd)
//   and the reactive contract triggers when sqrtPriceX96 > threshold.
(function () {
  "use strict";

  var cfg = window.STOPLOSS_CONFIG;
  var Q96 = 2n ** 96n;
  var UINT160_MAX = 2n ** 160n - 1n;
  var MAX_ORDERS_SHOWN = 10;

  var provider = null;        // BrowserProvider (MetaMask, Base Sepolia)
  var signer = null;
  var account = null;
  var vault = null;           // signer-connected vault (writes)
  var weth = null;            // signer-connected WETH (writes)
  var usdc = null;            // signer-connected USDC (reads)
  var vaultRead = null;       // read-only vault via public Base Sepolia RPC
  var rscRead = null;         // read-only reactive contract via public Lasna RPC
  var currentSqrtP = null;    // BigInt, latest live sqrtPriceX96
  var currentPriceUsd = null; // Number, latest live WETH price in USD

  // ---------- DOM ----------
  function $(id) { return document.getElementById(id); }
  var statusLine = $("statusLine");

  function setStatus(msg, kind) {
    statusLine.textContent = msg;
    statusLine.className = "status " + (kind || "info");
  }

  function txLink(hash, label) {
    var a = document.createElement("a");
    a.href = cfg.baseSepolia.explorerUrl + "/tx/" + hash;
    a.target = "_blank";
    a.rel = "noopener";
    a.textContent = label || hash;
    a.className = "mono";
    return a;
  }

  function showTx(el, label, hash) {
    el.textContent = "";
    el.appendChild(document.createTextNode(label + " "));
    el.appendChild(txLink(hash, hash.slice(0, 10) + "…" + hash.slice(-8)));
  }

  function shortAddr(addr) {
    return addr.slice(0, 6) + "…" + addr.slice(-4);
  }

  function fmtUsd(n) {
    if (n === null || n === undefined || !isFinite(n)) return "—";
    return "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  // ---------- Errors in plain language ----------
  var REVERT_EXPLAIN = {
    InsufficientBalance: "Not enough vault balance for that amount. Deposit WETH first.",
    OrderNotActive: "That order is no longer active (already executed or cancelled).",
    NotOrderOwner: "Only the order's owner can cancel it.",
    ZeroAmount: "The amount must be above zero.",
    NotPool: "Rejected by the vault's swap callback guard — this should not happen from the UI.",
  };

  function friendlyError(err) {
    if (!err) return "Unknown error.";
    var code = err.code;
    if (code === 4001 || code === "ACTION_REJECTED") {
      return "Transaction rejected in your wallet. Nothing was sent.";
    }
    var text = String((err && err.reason) || (err && err.message) || err);
    for (var name in REVERT_EXPLAIN) {
      if (text.indexOf(name) !== -1) return REVERT_EXPLAIN[name];
    }
    if (text.indexOf("insufficient funds") !== -1) {
      return "Not enough ETH for gas, or not enough WETH/USDC for the action.";
    }
    if (text.indexOf("user rejected") !== -1) return "Transaction rejected in your wallet. Nothing was sent.";
    return text.length > 220 ? text.slice(0, 220) + "…" : text;
  }

  // ---------- BigInt math ----------
  // Integer square root (Newton iteration) for BigInt.
  function isqrt(n) {
    if (n < 0n) throw new Error("isqrt of negative number");
    if (n < 2n) return n;
    var x = n;
    var y = (x + 1n) / 2n;
    while (y < x) {
      x = y;
      y = (x + n / x) / 2n;
    }
    return x;
  }

  // WETH price in USD from a sqrtPriceX96 value (Number — display only).
  function priceFromSqrtP(sqrtP) {
    var ratio = Number(sqrtP) / Number(Q96);
    return 1e12 / (ratio * ratio);
  }

  // sqrtPriceX96 threshold from a stop price in USD (decimal string).
  // threshold = 2^96 * sqrt(10^12 / priceUsd), computed in exact BigInt math:
  // priceUsd is parsed to 6-decimal fixed point, then
  // sqrt(10^12 / priceUsd) = isqrt(10^36 / priceUsd6) / 10^9.
  function thresholdFromStopPrice(priceStr) {
    var price6 = ethers.parseUnits(String(priceStr).trim(), 6); // price * 10^6
    if (price6 <= 0n) throw new Error("Stop price must be above zero.");
    var scaled = isqrt((10n ** 36n) / price6); // sqrt(r) * 10^9
    var threshold = (Q96 * scaled) / (10n ** 9n);
    if (threshold <= 0n || threshold > UINT160_MAX) {
      throw new Error("Stop price out of range for a uint160 threshold.");
    }
    return threshold;
  }

  // ---------- Wallet / network ----------
  function enableActions(enabled) {
    ["wrapBtn", "approveBtn", "depositBtn", "withdrawBtn", "createOrderBtn", "refreshOrdersBtn"]
      .forEach(function (id) { $(id).disabled = !enabled; });
  }

  async function ensureBaseSepolia() {
    var current = await window.ethereum.request({ method: "eth_chainId" });
    if (current.toLowerCase() === cfg.baseSepolia.chainIdHex) return;
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: cfg.baseSepolia.chainIdHex }],
      });
    } catch (err) {
      if (err && err.code === 4902) {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: cfg.baseSepolia.chainIdHex,
            chainName: cfg.baseSepolia.name,
            nativeCurrency: cfg.baseSepolia.nativeCurrency,
            rpcUrls: [cfg.baseSepolia.rpcUrl],
            blockExplorerUrls: [cfg.baseSepolia.explorerUrl],
          }],
        });
      } else {
        throw err;
      }
    }
  }

  async function connectWallet() {
    if (!window.ethereum) {
      setStatus("No wallet found. Install MetaMask (or another EVM wallet) and try again.", "error");
      return;
    }
    try {
      setStatus("Connecting wallet…", "info");
      await ensureBaseSepolia();
      provider = new ethers.BrowserProvider(window.ethereum);
      await provider.send("eth_requestAccounts", []);
      signer = await provider.getSigner();
      account = await signer.getAddress();
      vault = new ethers.Contract(cfg.contracts.vault, cfg.abis.vault, signer);
      weth = new ethers.Contract(cfg.contracts.weth, cfg.abis.weth, signer);
      usdc = new ethers.Contract(cfg.contracts.usdc, cfg.abis.erc20, signer);
      $("accountLine").textContent = shortAddr(account) + " · " + cfg.baseSepolia.name;
      $("connectBtn").textContent = "Connected";
      enableActions(true);
      setStatus("Connected to " + cfg.baseSepolia.name + ".", "success");
      await refreshBalances();
      await loadOrders();
      await refreshLive();
    } catch (err) {
      setStatus("Could not connect: " + friendlyError(err), "error");
    }
  }

  // ---------- Live data (no wallet needed) ----------
  function initReadProviders() {
    try {
      var baseRpc = new ethers.JsonRpcProvider(cfg.baseSepolia.rpcUrl);
      vaultRead = new ethers.Contract(cfg.contracts.vault, cfg.abis.vault, baseRpc);
    } catch (err) { vaultRead = null; }
    try {
      var lasnaRpc = new ethers.JsonRpcProvider(cfg.lasna.rpcUrl);
      rscRead = new ethers.Contract(cfg.contracts.reactive, cfg.abis.reactive, lasnaRpc);
    } catch (err) { rscRead = null; }
  }

  async function refreshLive() {
    // Pool price via the vault (reads pool.slot0 on-chain).
    if (vaultRead) {
      try {
        var sqrtP = await vaultRead.currentSqrtPriceX96();
        currentSqrtP = BigInt(sqrtP);
        currentPriceUsd = priceFromSqrtP(currentSqrtP);
        $("poolPrice").textContent = fmtUsd(currentPriceUsd);
        $("poolPriceNote").textContent = " per WETH";
        $("sqrtP").textContent = currentSqrtP.toString();
      } catch (err) {
        $("poolPrice").textContent = "—";
        $("poolPriceNote").textContent = " (could not read pool price — RPC unreachable?)";
        $("sqrtP").textContent = "—";
      }
    }
    // Reactive contract state via the Lasna public RPC.
    if (rscRead) {
      try {
        var armed = await rscRead.armed();
        var threshold = await rscRead.stopThreshold();
        var orderId = await rscRead.armedOrderId();
        var pill = $("rscArmed");
        if (armed) {
          pill.textContent = "ARMED";
          pill.className = "pill armed";
          $("rscDetail").textContent = " — a stop is live; the next Swap crossing the threshold triggers the callback.";
        } else {
          pill.textContent = "not armed";
          pill.className = "pill inactive";
          $("rscDetail").textContent = " — no stop is armed right now.";
        }
        if (BigInt(threshold) === 0n) {
          $("rscThreshold").textContent = "— (none set)";
        } else {
          $("rscThreshold").textContent =
            fmtUsd(priceFromSqrtP(BigInt(threshold))) +
            " per WETH (sqrtPriceX96 " + BigInt(threshold).toString() + ")";
        }
        $("rscOrder").textContent = armed ? ("Order #" + orderId.toString()) : "—";
      } catch (err) {
        $("rscArmed").textContent = "unreachable";
        $("rscArmed").className = "pill inactive";
        $("rscDetail").textContent = " — could not read Lasna (public RPC unreachable?).";
        $("rscThreshold").textContent = "—";
        $("rscOrder").textContent = "—";
      }
    }
    $("liveUpdated").textContent = "Updated " + new Date().toLocaleTimeString() + ".";
    updateThresholdPreview();
  }

  // ---------- Balances ----------
  async function refreshBalances() {
    if (!provider || !account) return;
    try {
      var eth = await provider.getBalance(account);
      $("ethBalance").textContent = ethers.formatEther(eth) + " ETH";
      var w = await weth.balanceOf(account);
      $("wethBalance").textContent = ethers.formatEther(w) + " WETH";
      var u = await usdc.balanceOf(account);
      $("usdcBalance").textContent = ethers.formatUnits(u, cfg.usdcDecimals) + " USDC";
      var v = await vault.balances(account);
      $("vaultBalance").textContent = ethers.formatEther(v) + " WETH";
    } catch (err) {
      setStatus("Could not read balances: " + friendlyError(err), "error");
    }
  }

  // ---------- Orders ----------
  async function loadOrders() {
    if (!vault) return;
    var list = $("orderList");
    list.innerHTML = "<p class=\"muted\">Loading orders…</p>";
    try {
      var next = Number(await vault.nextOrderId());
      if (next === 0) {
        $("orderCount").textContent = "No orders on-chain yet.";
        list.innerHTML = "<p class=\"muted\">No orders yet — create the first one above.</p>";
        return;
      }
      var rows = [];
      var from = Math.max(0, next - MAX_ORDERS_SHOWN);
      for (var id = next - 1; id >= from; id--) {
        var o = await vault.orders(id);
        if (o.owner.toLowerCase() !== account.toLowerCase()) continue;
        rows.push({ id: id, order: o });
      }
      $("orderCount").textContent = next + " order(s) on-chain, showing your latest " +
        Math.min(MAX_ORDERS_SHOWN, next) + " (newest first).";
      if (rows.length === 0) {
        list.innerHTML = "<p class=\"muted\">You have no orders in the latest " +
          Math.min(MAX_ORDERS_SHOWN, next) + " on-chain orders.</p>";
        return;
      }
      list.innerHTML = "";
      rows.forEach(function (row) { list.appendChild(renderOrder(row)); });
    } catch (err) {
      list.innerHTML = "";
      setStatus("Could not load orders: " + friendlyError(err), "error");
    }
  }

  function renderOrder(row) {
    var id = row.id, o = row.order;
    var stopUsd = fmtUsd(priceFromSqrtP(BigInt(o.stopThreshold)));
    var div = document.createElement("div");
    div.className = "order";
    div.id = "order-" + id;

    var top = document.createElement("div");
    top.className = "top";
    var left = document.createElement("div");
    var amt = document.createElement("span");
    amt.className = "amount";
    amt.textContent = ethers.formatEther(o.amountWeth) + " WETH";
    var memo = document.createElement("span");
    memo.className = "muted";
    memo.textContent = "  #" + id + " · stop " + stopUsd + " per WETH";
    left.appendChild(amt);
    left.appendChild(memo);
    var pill = document.createElement("span");
    pill.className = "pill " + (o.active ? "active" : "inactive");
    pill.textContent = o.active ? "Active" : "Closed";
    top.appendChild(left);
    top.appendChild(pill);
    div.appendChild(top);

    var meta = document.createElement("p");
    meta.className = "muted mono";
    meta.style.margin = "6px 0";
    meta.textContent = "threshold sqrtPriceX96 " + BigInt(o.stopThreshold).toString();
    div.appendChild(meta);

    if (o.active) {
      var actions = document.createElement("p");
      actions.style.margin = "8px 0 0";
      var cancelBtn = document.createElement("button");
      cancelBtn.className = "danger small";
      cancelBtn.textContent = "Cancel order (WETH back to vault balance)";
      cancelBtn.onclick = function () { cancelOrder(id); };
      actions.appendChild(cancelBtn);
      div.appendChild(actions);
      var txEl = document.createElement("p");
      txEl.className = "txline muted";
      txEl.id = "order-tx-" + id;
      div.appendChild(txEl);
    }
    return div;
  }

  // ---------- Threshold preview ----------
  function updateThresholdPreview() {
    var el = $("thresholdPreview");
    var stopStr = $("stopPrice").value;
    if (!stopStr || Number(stopStr) <= 0) {
      el.textContent = "Enter a stop price to see the on-chain threshold.";
      return;
    }
    try {
      var threshold = thresholdFromStopPrice(stopStr);
      var msg = "On-chain threshold: sqrtPriceX96 " + threshold.toString() + ".";
      if (currentSqrtP !== null) {
        if (threshold <= currentSqrtP) {
          msg += " ⚠️ This stop is ABOVE the live price (" + fmtUsd(currentPriceUsd) +
            ") — it is already crossed and would trigger on the next pool swap. " +
            "Enter a stop price below the live price.";
        } else {
          var pct = (1 - Number(stopStr) / currentPriceUsd) * 100;
          msg += " (" + pct.toFixed(2) + "% below the live price " + fmtUsd(currentPriceUsd) + ").";
        }
      }
      el.textContent = msg;
    } catch (err) {
      el.textContent = "Invalid stop price: " + err.message;
    }
  }

  // ---------- Actions ----------
  function parseWethInput(id) {
    var v = $(id).value;
    if (!v || Number(v) <= 0) return null;
    return ethers.parseEther(String(v).trim());
  }

  async function wrapEth() {
    var amount = parseWethInput("wrapAmount");
    if (amount === null) {
      setStatus("Enter an ETH amount above zero to wrap.", "error");
      return;
    }
    try {
      setStatus("Wrapping ETH → WETH — confirm in your wallet…", "info");
      var tx = await weth.deposit({ value: amount });
      setStatus("Wrap submitted, waiting for confirmation…", "info");
      var receipt = await tx.wait();
      showTx($("wrapResult"), "Wrapped.", tx.hash);
      setStatus("Wrapped " + ethers.formatEther(amount) + " ETH → WETH (block " +
        receipt.blockNumber + ").", "success");
      $("wrapAmount").value = "";
      await refreshBalances();
    } catch (err) {
      setStatus("Wrap failed: " + friendlyError(err), "error");
    }
  }

  async function approveVault() {
    var amount = parseWethInput("depositAmount");
    if (amount === null) {
      setStatus("Enter a WETH amount above zero first.", "error");
      return;
    }
    try {
      setStatus("Approving the vault to spend exactly " + ethers.formatEther(amount) +
        " WETH — confirm in your wallet…", "info");
      var tx = await weth.approve(cfg.contracts.vault, amount);
      await tx.wait();
      showTx($("depositResult"), "Vault approved.", tx.hash);
      setStatus("Vault approved for exactly " + ethers.formatEther(amount) +
        " WETH. Now deposit.", "success");
    } catch (err) {
      setStatus("Approval failed: " + friendlyError(err), "error");
    }
  }

  async function depositWeth() {
    var amount = parseWethInput("depositAmount");
    if (amount === null) {
      setStatus("Enter a WETH amount above zero to deposit.", "error");
      return;
    }
    try {
      setStatus("Depositing WETH — confirm in your wallet…", "info");
      var tx = await vault.depositWETH(amount);
      await tx.wait();
      showTx($("depositResult"), "Deposited.", tx.hash);
      setStatus("Deposited " + ethers.formatEther(amount) + " WETH into the vault.", "success");
      $("depositAmount").value = "";
      await refreshBalances();
    } catch (err) {
      setStatus("Deposit failed: " + friendlyError(err), "error");
    }
  }

  async function withdrawWeth() {
    var amount = parseWethInput("depositAmount");
    if (amount === null) {
      setStatus("Enter a WETH amount above zero to withdraw.", "error");
      return;
    }
    try {
      setStatus("Withdrawing WETH — confirm in your wallet…", "info");
      var tx = await vault.withdrawWETH(amount);
      await tx.wait();
      showTx($("depositResult"), "Withdrawn.", tx.hash);
      setStatus("Withdrew " + ethers.formatEther(amount) + " WETH back to your wallet.", "success");
      $("depositAmount").value = "";
      await refreshBalances();
    } catch (err) {
      setStatus("Withdraw failed: " + friendlyError(err), "error");
    }
  }

  async function createOrder() {
    var amount = parseWethInput("orderAmount");
    var stopStr = $("stopPrice").value;
    if (amount === null) {
      setStatus("Enter a WETH amount above zero for the order.", "error");
      return;
    }
    if (!stopStr || Number(stopStr) <= 0) {
      setStatus("Enter a stop price above zero.", "error");
      return;
    }
    var threshold;
    try {
      threshold = thresholdFromStopPrice(stopStr);
    } catch (err) {
      setStatus("Invalid stop price: " + err.message, "error");
      return;
    }
    if (currentSqrtP !== null && threshold <= currentSqrtP) {
      setStatus("Stop price must be BELOW the live price (" + fmtUsd(currentPriceUsd) +
        ") — this stop is already crossed and would trigger immediately.", "error");
      return;
    }
    try {
      setStatus("Creating order — confirm in your wallet…", "info");
      var tx = await vault.createOrder(amount, threshold);
      setStatus("Order submitted, waiting for confirmation…", "info");
      var receipt = await tx.wait();
      showTx($("orderResult"), "Order created.", tx.hash);
      setStatus("Order created for " + ethers.formatEther(amount) + " WETH at stop " +
        fmtUsd(Number(stopStr)) + " (block " + receipt.blockNumber +
        "). Ask the operator to arm it on Lasna — see DEMO.md.", "success");
      $("orderAmount").value = "";
      $("stopPrice").value = "";
      updateThresholdPreview();
      await refreshBalances();
      await loadOrders();
    } catch (err) {
      setStatus("Could not create the order: " + friendlyError(err), "error");
    }
  }

  async function cancelOrder(id) {
    try {
      setStatus("Cancelling order #" + id + " — confirm in your wallet…", "info");
      var tx = await vault.cancelOrder(id);
      await tx.wait();
      var txEl = $("order-tx-" + id);
      if (txEl) showTx(txEl, "Cancelled.", tx.hash);
      setStatus("Order #" + id + " cancelled — its WETH is back in your vault balance.", "success");
      await refreshBalances();
      await loadOrders();
    } catch (err) {
      setStatus("Could not cancel: " + friendlyError(err), "error");
    }
  }

  // ---------- Init ----------
  initReadProviders();
  refreshLive();
  setInterval(refreshLive, 30000);
  $("connectBtn").addEventListener("click", connectWallet);
  $("refreshLiveBtn").addEventListener("click", refreshLive);
  $("wrapBtn").addEventListener("click", wrapEth);
  $("approveBtn").addEventListener("click", approveVault);
  $("depositBtn").addEventListener("click", depositWeth);
  $("withdrawBtn").addEventListener("click", withdrawWeth);
  $("createOrderBtn").addEventListener("click", createOrder);
  $("refreshOrdersBtn").addEventListener("click", loadOrders);
  $("stopPrice").addEventListener("input", updateThresholdPreview);
  if (window.ethereum) {
    window.ethereum.on("accountsChanged", function () { window.location.reload(); });
    window.ethereum.on("chainChanged", function () { window.location.reload(); });
  }
})();
