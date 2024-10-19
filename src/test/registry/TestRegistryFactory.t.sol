// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, RegistryFactory, ReleaseRegistry, Registry} from "../utils/Setup.sol";

contract TestRegistryFactory is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test__factory_set_up() public {
        assertEq(
            address(registryFactory.releaseRegistry()),
            address(releaseRegistry)
        );
        assertEq(registryFactory.name(), "Yearn V3 Vault Registry Factory");
    }

    function test__new_registry() public {
        string memory new_name = "new test registry";

        vm.prank(management);
        vm.expectEmit(false, true, true, true, address(registryFactory));
        emit NewRegistry(address(0), management, new_name);
        address newRegistryAddress = registryFactory.createNewRegistry(
            new_name
        );

        Registry newRegistry = Registry(newRegistryAddress);

        assertEq(newRegistry.governance(), management);
        assertEq(
            address(newRegistry.releaseRegistry()),
            address(releaseRegistry)
        );
        assertEq(newRegistry.name(), new_name);
        assertEq(newRegistry.numAssets(), 0);
    }

    event NewRegistry(
        address indexed newRegistry,
        address indexed governance,
        string name
    );
}
