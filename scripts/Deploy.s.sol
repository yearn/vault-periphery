// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {
    // Create X address.
    Deployer public deployer =
        Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address public initGov = 0x6f3cBE2ab3483EC4BA7B672fbdCa0E9B33F88db8;

    function run() external {
        vm.startBroadcast();

        // Append constructor args to the bytecode
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("splitter/Dumper.sol:Dumper"),
            abi.encode(0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7, 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69, 0xd6748776CF06a80EbE36cd83D325B31bb916bf54, 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204)
        );

        // Use salt of 0.
        bytes32 salt;

        address contractAddress = deployer.deployCreate2(salt, bytecode);

        console.log("Address is ", contractAddress);

        vm.stopBroadcast();
    }
}

contract Deployer {
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deployCreate2(
        bytes32 salt,
        bytes memory initCode
    ) public payable returns (address newContract) {}
}
