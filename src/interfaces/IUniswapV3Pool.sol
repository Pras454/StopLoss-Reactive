// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/// @notice Minimal Uniswap V3 pool interface — only the functions the vault needs.
/// @dev Base Sepolia has NO SwapRouter/Quoter (verified 0 bytes on-chain), so the
///      vault calls pool.swap() directly and implements the swap callback itself.
interface IUniswapV3Pool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

/// @notice Callback the pool invokes on the swap initiator to collect payment.
interface IUniswapV3SwapCallback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}
