// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

contract MockFactory {
    string public api_version;

    address public vault_bluePrint;

    constructor(string memory apiVersion) {
        api_version = apiVersion;
    }
}
