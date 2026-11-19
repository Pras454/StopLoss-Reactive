// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { IERC20 } from "./interfaces/IERC20.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IUniswapV3Pool, IUniswapV3SwapCallback } from "./interfaces/IUniswapV3Pool.sol";
import { TickMath } from "./interfaces/TickMath.sol";

/// @title Swapper
/// @notice Demo-only helper: sells WETH into the Uniswap V3 pool to move the
///         price (the "market crash" that triggers the stop-loss).
/// @dev The deployer is an EOA and cannot receive uniswapV3SwapCallback, so
///      this contract performs the swap. NOT part of the submitted product —
///      it only simulates the market event the reactive contract catches.
contract Swapper is IUniswapV3SwapCallback {
    IUniswapV3Pool public immutable POOL;
    IERC20 public immutable WETH;
    IERC20 public immutable USDC;
    address public immutable owner;

    constructor(address pool_, address weth_, address usdc_) {
        POOL = IUniswapV3Pool(pool_);
        WETH = IERC20(weth_);
        USDC = IERC20(usdc_);
        owner = msg.sender;
    }

    receive() external payable {}

    /// @notice Wrap the sent ETH and sell it all into the pool (token1 -> token0).
    function wrapAndSell() external payable {
        require(msg.sender == owner, "not owner");
        require(msg.value > 0, "no ETH");
        IWETH(address(WETH)).deposit{ value: msg.value }();
        _sell(msg.value);
    }

    /// @notice Sell WETH already held by this contract.
    function sellWeth(uint256 amount_) external {
        require(msg.sender == owner, "not owner");
        _sell(amount_);
    }

    function _sell(uint256 amount_) internal {
        POOL.swap(address(this), false, int256(amount_), TickMath.MAX_SQRT_RATIO - 1, "");
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        require(msg.sender == address(POOL), "not pool");
        if (amount1Delta > 0) {
            require(WETH.transfer(address(POOL), uint256(amount1Delta)), "WETH pay failed");
        }
        if (amount0Delta > 0) {
            require(USDC.transfer(address(POOL), uint256(amount0Delta)), "USDC pay failed");
        }
    }

    /// @notice Send received USDC back to the owner.
    function withdrawUSDC() external {
        require(msg.sender == owner, "not owner");
        uint256 bal = USDC.balanceOf(address(this));
        require(USDC.transfer(owner, bal), "USDC withdraw failed");
    }
}
