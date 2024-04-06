// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

contract Deployer {
    event Deployed(address addr, uint256 salt);
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deploy(bytes memory code, uint256 salt) external {}

    function deployCreate2(
        bytes32 salt,
        bytes memory initCode
    ) public payable returns (address newContract) {}
}
