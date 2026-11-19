// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { StopLossReactive } from "../src/StopLossReactive.sol";

/// @notice Deploys StopLossReactive on Lasna (chain 5318007).
/// @dev Pool + Swap topic0 are hardcoded constants in the contract.
///      Run (parent deploys — DO NOT broadcast from this subagent):
///        PRIVATE_KEY=$PRIVATE_KEY forge script script/DeployReactive.s.sol \
///          --rpc-url https://lasna-rpc.rnk.dev/ --broadcast
///      The deploy funds the contract with 1 lREACT so it can pay reactive
///      tx fees from day one (debt blocks execution — RESEARCH.md §8).
contract DeployReactive is Script {
    uint256 internal constant DEPLOY_FUND_LREACT = 1 ether;

    function run() external returns (StopLossReactive reactive) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        reactive = new StopLossReactive{ value: DEPLOY_FUND_LREACT }();
        vm.stopBroadcast();
        console.log("StopLossReactive deployed at:", address(reactive));
        console.log("Pool watched:", reactive.POOL());
        console.log("Swap topic0:", reactive.SWAP_TOPIC0());
    }
}
