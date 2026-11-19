// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/// @notice Uniswap V3 tick-math price bounds (copied constants, no dependency).
/// @dev MIN_SQRT_RATIO = sqrt(1.0001^-887272) * 2^96, MAX_SQRT_RATIO = sqrt(1.0001^887272) * 2^96.
///      In pool.swap(), sqrtPriceLimitX96 is a FLOOR when zeroForOne is true and a
///      CEILING when zeroForOne is false — so a token1 -> token0 sell uses
///      MAX_SQRT_RATIO - 1 as the "no effective limit" value.
library TickMath {
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
}
