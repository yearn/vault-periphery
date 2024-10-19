// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

///@notice This cheat codes interface is named _CheatCodes so you can use the CheatCodes interface in other testing files without errors
interface _CheatCodes {
    function ffi(string[] calldata) external returns (bytes memory);
}

// Deploy a contract to a deterministic address with create2 factory.
contract DeployVyper is Script {
    address constant HEVM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Initializes cheat codes in order to use ffi to compile Vyper contracts
    _CheatCodes cheatCodes = _CheatCodes(HEVM_ADDRESS);

    // Create X address.
    Deployer public deployer =
        Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address public initGov = 0x6f3cBE2ab3483EC4BA7B672fbdCa0E9B33F88db8;

    function run() external {
        vm.startBroadcast();

        ///@notice compile the Vyper contract and return the bytecode
        bytes memory bytecode = compileVyper(
            "src/addressProviders/",
            "ProtocolAddressProvider"
        );

        bytecode = abi.encodePacked(bytecode, abi.encode(initGov));

        // Use salt of 0.
        bytes32 salt;

        address contractAddress = deployer.deployCreate2(salt, bytecode);

        console.log("Address is ", contractAddress);

        vm.stopBroadcast();
    }

    function compileVyper(
        string memory path,
        string memory fileName
    ) public returns (bytes memory) {
        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = string.concat(path, fileName, ".vy");

        return cheatCodes.ffi(cmds);
    }
}

contract Deployer {
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deployCreate2(
        bytes32 salt,
        bytes memory initCode
    ) public payable returns (address newContract) {}
}
