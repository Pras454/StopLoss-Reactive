// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { IERC20 } from "./IERC20.sol";

/// @notice Minimal WETH interface (wrap/unwrap + ERC-20).
interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
