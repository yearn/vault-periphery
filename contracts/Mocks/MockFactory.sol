// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

contract MockFactory {
    string public apiVersion;

    address public vault_bluePrint;

    constructor(string memory _apiVersion) {
        apiVersion = _apiVersion;
    }
}
