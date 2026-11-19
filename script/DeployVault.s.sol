// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { StopLossVault } from "../src/StopLossVault.sol";

/// @notice Deploys StopLossVault on Base Sepolia (chain 84532).
/// @dev Deploy AFTER StopLossReactive (its address is the immutable callback
///      sender). Pass it via REACTIVE_ADDR.
///      Run (parent deploys — DO NOT broadcast from this subagent):
///        PRIVATE_KEY=$PRIVATE_KEY REACTIVE_ADDR=0x... forge script script/DeployVault.s.sol \
///          --rpc-url https://sepolia.base.org --broadcast
///      The deploy funds the vault with 0.01 Base Sepolia ETH so callback
///      billing (which lands on the recipient) can be paid.
contract DeployVault is Script {
    address internal constant CALLBACK_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    address internal constant POOL = 0x46880b404CD35c165EDdefF7421019F8dD25F4Ad;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    uint256 internal constant DEPLOY_FUND_ETH = 0.01 ether;

    function run() external returns (StopLossVault vault) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address reactive = vm.envAddress("REACTIVE_ADDR");
        require(reactive != address(0), "REACTIVE_ADDR env var required");

        vm.startBroadcast(deployerKey);
        vault = new StopLossVault{ value: DEPLOY_FUND_ETH }(
            IPayable(payable(CALLBACK_PROXY)), reactive, POOL, WETH, USDC
        );
        vm.stopBroadcast();
        console.log("StopLossVault deployed at:", address(vault));
        console.log("Callback sender (reactive):", reactive);
        console.log("Pool:", address(vault.POOL()));
    }
}
