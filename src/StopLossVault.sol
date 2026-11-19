// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IUniswapV3Pool, IUniswapV3SwapCallback } from "./interfaces/IUniswapV3Pool.sol";
import { TickMath } from "./interfaces/TickMath.sol";

/// @title StopLossVault
/// @notice Callback contract (Omni model) on Base Sepolia for the Reactive Omni
///         Buildathon, Track 1. Holds users' WETH against stop-loss orders and,
///         on a callback from the StopLossReactive contract, sells the WETH for
///         USDC and pays the order owner.
///
/// @dev Base Sepolia has NO Uniswap SwapRouter/Quoter (verified 0 bytes
///      on-chain), so the vault calls pool.swap() directly and implements
///      uniswapV3SwapCallback itself. The swap sells token1 (WETH) for token0
///      (USDC): zeroForOne = false, exact input. For zeroForOne = false the
///      sqrtPriceLimitX96 is a CEILING, so the "no effective limit" value is
///      MAX_SQRT_RATIO - 1 (using MIN_SQRT_RATIO here would revert the swap).
contract StopLossVault is AbstractCallback, IUniswapV3SwapCallback {
    /// @notice Uniswap V3 WETH/USDC pool, fee 3000, on Base Sepolia.
    IUniswapV3Pool public immutable POOL;

    /// @notice WETH on Base Sepolia (token1 of the pool, 18 dec).
    IERC20 public immutable WETH;

    /// @notice USDC on Base Sepolia (token0 of the pool, 6 dec).
    IERC20 public immutable USDC;

    struct Order {
        address owner;
        uint256 amountWeth;
        uint160 stopThreshold;
        bool active;
    }

    /// @notice Orders by id.
    mapping(uint256 => Order) public orders;

    /// @notice Next order id (starts at 0).
    uint256 public nextOrderId;

    /// @notice WETH deposited by each user, not yet allocated to an order.
    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event OrderCreated(uint256 indexed orderId, address indexed owner, uint256 amountWeth, uint160 stopThreshold);
    event OrderCancelled(uint256 indexed orderId);
    event StopLossExecuted(uint256 indexed orderId, address indexed owner, uint256 usdcReceived);

    error InsufficientBalance(uint256 requested, uint256 available);
    error OrderNotActive(uint256 orderId);
    error NotPool(address caller);
    error NotOrderOwner(address caller, address owner);
    error ZeroAmount();

    /// @param callbackProxy_ Base Sepolia callback proxy (0x476F44b11F5C942c58f4c8E3d0300E5710743585).
    /// @param callbackSender_ StopLossReactive contract address on Lasna.
    /// @param pool_ Uniswap V3 WETH/USDC pool on Base Sepolia.
    /// @param weth_ WETH on Base Sepolia.
    /// @param usdc_ USDC on Base Sepolia.
    constructor(
        IPayable callbackProxy_,
        address callbackSender_,
        address pool_,
        address weth_,
        address usdc_
    ) payable AbstractCallback(callbackProxy_, callbackSender_) {
        POOL = IUniswapV3Pool(pool_);
        WETH = IERC20(weth_);
        USDC = IERC20(usdc_);
    }

    /// @notice Deposit WETH into the vault (approve the vault first).
    function depositWETH(uint256 amount_) external {
        if (amount_ == 0) revert ZeroAmount();
        require(WETH.transferFrom(msg.sender, address(this), amount_), "WETH transfer failed");
        balances[msg.sender] += amount_;
        // event logged after the transfer by design (it reports success)
        // forge-lint: disable-next-line(reentrancy-events)
        emit Deposited(msg.sender, amount_);
    }

    /// @notice Withdraw unallocated WETH (not locked in an active order).
    function withdrawWETH(uint256 amount_) external {
        if (amount_ == 0) revert ZeroAmount();
        if (balances[msg.sender] < amount_) revert InsufficientBalance(amount_, balances[msg.sender]);
        balances[msg.sender] -= amount_;
        require(WETH.transfer(msg.sender, amount_), "WETH transfer failed");
        // event logged after the transfer by design (it reports success)
        // forge-lint: disable-next-line(reentrancy-events)
        emit Withdrawn(msg.sender, amount_);
    }

    /// @notice Create a stop-loss order against deposited WETH.
    /// @param amountWeth_ WETH to sell when the stop triggers.
    /// @param stopThreshold_ Stop price as a sqrtPriceX96 value. NOTE the
    ///        direction: WETH falling ⟺ sqrtPriceX96 rising, so this threshold
    ///        sits ABOVE the current pool sqrtPriceX96. Compute off-chain from
    ///        the target USD price: threshold = 2^96 * sqrt(10^12 / priceUsd).
    ///        The pool's testnet price is stale, so set the threshold RELATIVE
    ///        to the current pool price (read vault.currentSqrtPriceX96()).
    /// @return orderId_ The new order id — the operator arms this id in the
    ///         reactive contract (arm(orderId, threshold)) after creation.
    function createOrder(uint256 amountWeth_, uint160 stopThreshold_) external returns (uint256 orderId_) {
        if (amountWeth_ == 0) revert ZeroAmount();
        // type(int256).max is positive, so this cast cannot truncate
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 maxInt = uint256(type(int256).max);
        if (amountWeth_ > maxInt) revert InsufficientBalance(amountWeth_, maxInt);
        if (balances[msg.sender] < amountWeth_) revert InsufficientBalance(amountWeth_, balances[msg.sender]);
        balances[msg.sender] -= amountWeth_;

        orderId_ = nextOrderId++;
        orders[orderId_] = Order({
            owner: msg.sender,
            amountWeth: amountWeth_,
            stopThreshold: stopThreshold_,
            active: true
        });
        emit OrderCreated(orderId_, msg.sender, amountWeth_, stopThreshold_);
    }

    /// @notice Cancel an active order and return its WETH to the unallocated balance.
    /// @dev The operator should also disarm the reactive contract afterwards.
    function cancelOrder(uint256 orderId_) external {
        Order storage order = orders[orderId_];
        if (!order.active) revert OrderNotActive(orderId_);
        if (order.owner != msg.sender) revert NotOrderOwner(msg.sender, order.owner);
        order.active = false;
        balances[msg.sender] += order.amountWeth;
        emit OrderCancelled(orderId_);
    }

    /// @notice Execute a stop-loss order. Called ONLY via the Reactive Network
    ///         callback: msg.sender must be the callback proxy AND the injected
    ///         first payload argument must be the authorized reactive contract.
    /// @param reactive_ Injected reactive-contract address (first payload arg).
    /// @param orderId_ The order to execute.
    function executeStopLoss(address reactive_, uint256 orderId_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        Order storage order = orders[orderId_];
        if (!order.active) revert OrderNotActive(orderId_);
        // Checks-effects first: deactivate before the external swap call.
        order.active = false;

        uint256 usdcBefore = USDC.balanceOf(address(this));

        // Sell token1 (WETH) for token0 (USDC), exact input.
        // zeroForOne = false => sqrtPriceLimitX96 is a CEILING, so use the max.
        // cast is safe: createOrder enforces amountWeth <= type(int256).max
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 amountSpecified = int256(order.amountWeth);
        // swap return values intentionally ignored: proceeds are measured by
        // USDC balance diff below (robust to fee-on-transfer style tokens).
        // forge-lint: disable-next-line(unused-return)
        POOL.swap(address(this), false, amountSpecified, TickMath.MAX_SQRT_RATIO - 1, abi.encode(orderId_));

        uint256 usdcReceived = USDC.balanceOf(address(this)) - usdcBefore;
        require(USDC.transfer(order.owner, usdcReceived), "USDC transfer failed");
        // event logged after the transfer by design (it reports success)
        // forge-lint: disable-next-line(reentrancy-events)
        emit StopLossExecuted(orderId_, order.owner, usdcReceived);
    }

    /// @notice Uniswap V3 swap callback: the pool collects the WETH owed here.
    /// @dev Authenticated: only the pool may call. For our sell (token1 ->
    ///      token0, exact input) amount1Delta > 0 is the WETH we owe; amount0Delta
    ///      is negative (USDC we receive). Pay whichever delta is positive.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata /* data */)
        external
        override
    {
        if (msg.sender != address(POOL)) revert NotPool(msg.sender);
        if (amount0Delta > 0) {
            // casting to 'uint256' is safe because amount0Delta > 0 is checked above
            // forge-lint: disable-next-line(unsafe-typecast)
            require(USDC.transfer(address(POOL), uint256(amount0Delta)), "USDC payment failed");
        }
        if (amount1Delta > 0) {
            // casting to 'uint256' is safe because amount1Delta > 0 is checked above
            // forge-lint: disable-next-line(unsafe-typecast)
            require(WETH.transfer(address(POOL), uint256(amount1Delta)), "WETH payment failed");
        }
    }

    /// @notice Read the pool's current price (for UIs / the demo script).
    function currentSqrtPriceX96() external view returns (uint160 sqrtPriceX96) {
        // only the price is needed; the other slot0 fields are intentionally ignored
        // forge-lint: disable-next-line(unused-return)
        (sqrtPriceX96,,,,,,) = POOL.slot0();
    }

    /// @notice Settle any outstanding debt to the callback proxy from this
    ///         contract's own ETH balance, so callbacks keep being delivered.
    function coverDebt() external {
        _coverDebt();
    }
}
