// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";

contract MockOracle is AprOracle {
    constructor() AprOracle(msg.sender) {}
}
