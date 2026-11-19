// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/// @notice Minimal ERC-20 interface — only the functions the vault needs.
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}
