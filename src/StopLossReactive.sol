// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title StopLossReactive
/// @notice Reactive Smart Contract (Omni model) for the Reactive Omni Buildathon,
///         Track 1 — "Every Second Counts".
/// @dev Watches Swap events on the real Uniswap V3 WETH/USDC pool (fee 3000) on
///      Base Sepolia. Each Swap log carries the post-swap sqrtPriceX96, so the
///      reactive contract itself catches the moment the price crosses the stop —
///      no oracle, no off-chain bot. When the price drops below the armed stop
///      threshold it requests a callback to the StopLossVault, which sells the
///      vaulted WETH for USDC and pays the order owner.
///
///      PRICE DIRECTION — READ CAREFULLY: in this pool token0 = USDC, token1 =
///      WETH, and sqrtPriceX96^2 = y/x (token1 per token0, raw units). The WETH
///      price in USDC is 10^(18-6) / (sqrtPriceX96/2^96)^2 — i.e. the WETH price
///      and sqrtPriceX96 move in OPPOSITE directions. WETH falling ⟺ sqrtPriceX96
///      RISING. So a stop price is expressed as a sqrtPriceX96 value ABOVE the
///      current sqrtPriceX96, and the trigger fires when sqrtPriceX96 rises
///      STRICTLY above the threshold. (Selling WETH into the pool pushes the
///      tick and sqrtPriceX96 up — verified against the pool's live tick
///      174308 / sqrtPriceX96 4.8278e32, ≈ $26,932/WETH.)
///
///      Swap event (Uniswap V3 pool):
///        Swap(address indexed sender, address indexed recipient,
///             int256 amount0, int256 amount1, uint160 sqrtPriceX96,
///             uint128 liquidity, int24 tick)
///      topic0 = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)")
///             = 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67
///      The 5 non-indexed params arrive packed in log_.data (5 x 32 bytes);
///      sqrtPriceX96 is the 3rd word. opCode = 3 (LOG3: 2 indexed params).
contract StopLossReactive is AbstractReactive {
    /// @notice Base Sepolia chain ID (origin chain + callback destination).
    uint256 public constant ORIGIN_CHAIN_ID = 84532;

    /// @notice Uniswap V3 WETH/USDC pool, fee 3000, on Base Sepolia.
    ///         token0 = USDC (6 dec), token1 = WETH (18 dec).
    address public constant POOL = 0x46880b404CD35c165EDdefF7421019F8dD25F4Ad;

    /// @notice topic0 of the Uniswap V3 Swap event.
    uint256 public constant SWAP_TOPIC0 = 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67;

    /// @notice Gas limit requested for the callback tx (docs example size; the
    ///         proxy withholds its own accounting gas, so size generously).
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;

    /// @notice Contract owner (deployer) — manages vault address and arming.
    address public owner;

    /// @notice StopLossVault on Base Sepolia receiving the callbacks.
    address public vault;

    /// @notice Currently armed stop threshold, as a sqrtPriceX96 value.
    ///         The WETH price falling below the stop ⟺ sqrtPriceX96 rising
    ///         above this value, so the threshold sits ABOVE the current
    ///         sqrtPriceX96. Trigger fires when sqrtPriceX96 > threshold.
    uint160 public stopThreshold;

    /// @notice Order ID the armed stop belongs to (vault-side order id).
    uint256 public armedOrderId;

    /// @notice Whether a stop is currently armed.
    bool public armed;

    event ThresholdSet(uint160 threshold);
    event Armed(uint256 indexed orderId, uint160 threshold);
    event Disarmed(uint256 indexed orderId);
    event VaultSet(address indexed vault);
    event StopTriggered(uint256 indexed orderId, uint160 sqrtPriceX96, uint160 threshold);
    event CallbackRequested(uint256 indexed orderId, address indexed vault);

    error NotOwner(address caller);
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    /// @notice Deploys the reactive contract and subscribes to Swap events on
    ///         the pool. Payable so it can be funded with lREACT at deployment.
    constructor() payable {
        owner = msg.sender;
        SYSTEM.subscribe(ORIGIN_CHAIN_ID, POOL, SWAP_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @notice Pure threshold check, exposed for tests and off-chain tooling:
    ///         the WETH price is below the stop exactly when sqrtPriceX96 has
    ///         risen STRICTLY above the threshold (see the price-direction note
    ///         at the top of this file).
    function isBelowStop(uint160 sqrtPriceX96_, uint160 threshold_) public pure returns (bool) {
        return sqrtPriceX96_ > threshold_;
    }

    /// @notice Entry point called by the system contract for each matching log.
    /// @dev NEVER reverts as a filter: a reverting react() is still billed in
    ///      full (RESEARCH.md §8). Every non-matching case falls through silently.
    function react(LogRecord calldata log_) external override onlySystem {
        // Route on the log's identity first.
        if (log_.chainId != ORIGIN_CHAIN_ID) return;
        if (log_.contractAddress != POOL) return;
        if (log_.topic0 != SWAP_TOPIC0) return;
        // Swap has 2 indexed params => LOG3; anything else is not a Swap log.
        if (log_.opCode != 3) return;
        // 5 non-indexed words = 160 bytes of data.
        if (log_.data.length < 160) return;
        // Nothing armed, or no vault configured yet.
        if (!armed || vault == address(0)) return;

        // Decode the post-swap price (3rd word of the packed data).
        (, , uint160 sqrtPriceX96, , ) = abi.decode(log_.data, (int256, int256, uint160, uint128, int24));

        // Price still at or above the stop: nothing to do.
        if (!isBelowStop(sqrtPriceX96, stopThreshold)) return;

        // Trigger: disarm FIRST (one trigger per order), then request the callback.
        uint256 orderId = armedOrderId;
        armed = false;
        emit StopTriggered(orderId, sqrtPriceX96, stopThreshold);

        // FIRST payload argument MUST be address(0): the network overwrites the
        // first 160 bits with this reactive contract's address, which the vault
        // authenticates via onlyCallbackSender.
        bytes memory payload =
            abi.encodeWithSignature("executeStopLoss(address,uint256)", address(0), orderId);
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: ORIGIN_CHAIN_ID,
                recipient: vault,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
        // event logged after the callback request by design (it reports success)
        // forge-lint: disable-next-line(reentrancy-events)
        emit CallbackRequested(orderId, vault);
    }

    /// @notice Set (or replace) the vault that receives stop-loss callbacks.
    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
        emit VaultSet(vault_);
    }

    /// @notice Change the stop threshold without re-arming.
    function setThreshold(uint160 threshold_) external onlyOwner {
        stopThreshold = threshold_;
        emit ThresholdSet(threshold_);
    }

    /// @notice Arm the stop for one vault order at a given threshold.
    /// @dev Call after the user creates the order in the vault. The threshold
    ///      is a sqrtPriceX96 value ABOVE the current pool sqrtPriceX96
    ///      (WETH falling ⟺ sqrtPriceX96 rising).
    function arm(uint256 orderId_, uint160 threshold_) external onlyOwner {
        armedOrderId = orderId_;
        stopThreshold = threshold_;
        armed = true;
        emit Armed(orderId_, threshold_);
    }

    /// @notice Disarm the current stop (e.g. the user cancelled the order).
    function disarm() external onlyOwner {
        uint256 orderId = armedOrderId;
        armed = false;
        emit Disarmed(orderId);
    }

    /// @notice Off-switch: remove the Swap subscription entirely.
    /// @dev Must match the original subscribe arguments exactly.
    function unsubscribeAll() external onlyOwner {
        SYSTEM.unsubscribe(ORIGIN_CHAIN_ID, POOL, SWAP_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @notice Settle any outstanding debt to the system contract from this
    ///         contract's own balance, so execution can resume (RESEARCH.md §8).
    ///         Callable by anyone — it can only pay the contract's own debt.
    function coverDebt() external {
        _coverDebt();
    }
}
