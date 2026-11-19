// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

contract ReactiveSmoke is AbstractReactive {
    constructor(uint256 originChainId_, address originContract_, uint256 topic0_) payable {
        SYSTEM.subscribe(originChainId_, originContract_, topic0_, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    function react(LogRecord memory log_) external override onlySystem {}
}
