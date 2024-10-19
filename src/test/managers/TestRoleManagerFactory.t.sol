// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, RoleManager, IVault, Roles, MockStrategy, DebtAllocator, Accountant, Registry} from "../utils/Setup.sol";
import {TestRoleManager} from "./TestRoleManager.t.sol";

contract TestRoleManagerFactory is TestRoleManager {
    event NewProject(bytes32 indexed projectId, address indexed roleManager);

    string public name = "Tezzz";

    // Deploy whole new project and run same tests with deployed Role Manager
    function setUp() public virtual override {
        super.setUp();

        setupAddressProvider();

        address newDaddy = address(234);
        address newBrain = address(3456);

        address _roleManager = roleManagerFactory.newProject(
            name,
            newDaddy,
            newBrain
        );

        roleManager = RoleManager(_roleManager);
        daddy = newDaddy;
        brain = newBrain;
        accountant = Accountant(roleManager.getAccountant());
        registry = Registry(roleManager.getRegistry());
        debtAllocator = DebtAllocator(roleManager.getDebtAllocator());

        vm.prank(daddy);
        accountant.acceptFeeManager();
    }

    function test_newProjectSetup() public {
        bytes32 id = roleManagerFactory.getProjectId(name, daddy);

        (
            address _roleManager,
            address _registry,
            address _accountant,
            address _debtAllocator
        ) = roleManagerFactory.projects(id);
        console2.log(roleManager.name());
        assertNeq(_roleManager, address(0));
        assertNeq(_registry, address(0));
        assertNeq(_accountant, address(0));
        assertNeq(_debtAllocator, address(0));

        assertEq(roleManager.name(), "Tezzz Role Manager");
    }

    function setupAddressProvider() public {
        vm.startPrank(daddy);
        addressProvider.setAccountantFactory(address(accountantFactory));
        addressProvider.setRegistryFactory(address(registryFactory));
        addressProvider.setRoleManagerFactory(address(roleManagerFactory));
        addressProvider.setDebtAllocatorFactory(address(debtAllocatorFactory));
        addressProvider.setKeeper(address(keeper));
        vm.stopPrank();
    }
}
