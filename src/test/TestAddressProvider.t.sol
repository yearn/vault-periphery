// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, IProtocolAddressProvider} from "./utils/Setup.sol";

contract TestAddressProvider is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_address_provider_setup() public {
        assertEq(addressProvider.name(), "Yearn V3 Protocol Address Provider");
        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), ZERO_ADDRESS);
        assertEq(addressProvider.getRouter(), ZERO_ADDRESS);
        assertEq(addressProvider.getKeeper(), ZERO_ADDRESS);
        assertEq(addressProvider.getAprOracle(), ZERO_ADDRESS);
        assertEq(addressProvider.getReleaseRegistry(), ZERO_ADDRESS);
        assertEq(addressProvider.getCommonReportTrigger(), ZERO_ADDRESS);
        assertEq(addressProvider.getAuctionFactory(), ZERO_ADDRESS);
        assertEq(addressProvider.getSplitterFactory(), ZERO_ADDRESS);
        assertEq(addressProvider.getRegistryFactory(), ZERO_ADDRESS);
        assertEq(addressProvider.getAllocatorFactory(), ZERO_ADDRESS);
        assertEq(addressProvider.getAccountantFactory(), ZERO_ADDRESS);
        assertEq(addressProvider.getRoleManagerFactory(), ZERO_ADDRESS);
        assertEq(addressProvider.getAddress(bytes32("random")), ZERO_ADDRESS);
    }

    function test__set_address() public {
        bytes32 id = bytes32("random");
        address newAddress = address(0x123);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setAddress(id, newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setAddress(id, newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
    }

    function test__set_router() public {
        bytes32 id = AddressIds.ROUTER;
        address newAddress = address(0x123);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getRouter(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setRouter(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getRouter(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setRouter(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getRouter(), newAddress);
    }

    function test__set_keeper() public {
        bytes32 id = AddressIds.KEEPER;
        address newAddress = address(keeper);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getKeeper(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setKeeper(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getKeeper(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setKeeper(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getKeeper(), newAddress);
    }

    function test__set_release_registry() public {
        bytes32 id = AddressIds.RELEASE_REGISTRY;
        address newAddress = address(releaseRegistry);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getReleaseRegistry(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setReleaseRegistry(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getReleaseRegistry(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setReleaseRegistry(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getReleaseRegistry(), newAddress);
    }

    function test__set_common_report_trigger() public {
        bytes32 id = AddressIds.COMMON_REPORT_TRIGGER;
        address newAddress = user;

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getCommonReportTrigger(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setCommonReportTrigger(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getCommonReportTrigger(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setCommonReportTrigger(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getCommonReportTrigger(), newAddress);
    }

    function test__set_apr_oracle() public {
        bytes32 id = AddressIds.APR_ORACLE;
        address newAddress = user;

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getAprOracle(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setAprOracle(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getAprOracle(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setAprOracle(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getAprOracle(), newAddress);
    }

    function test__set_base_fee_provider() public {
        bytes32 id = AddressIds.BASE_FEE_PROVIDER;
        address newAddress = user;

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getBaseFeeProvider(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setBaseFeeProvider(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getBaseFeeProvider(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setBaseFeeProvider(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getBaseFeeProvider(), newAddress);
    }

    function test__set_auction_factory() public {
        bytes32 id = AddressIds.AUCTION_FACTORY;
        address newAddress = address(registryFactory);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getAuctionFactory(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setAuctionFactory(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getAuctionFactory(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setAuctionFactory(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getAuctionFactory(), newAddress);
    }

    function test__set_splitter_factory() public {
        bytes32 id = AddressIds.SPLITTER_FACTORY;
        address newAddress = address(splitterFactory);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getSplitterFactory(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setSplitterFactory(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getSplitterFactory(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setSplitterFactory(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getSplitterFactory(), newAddress);
    }

    function test__set_registry_factory() public {
        bytes32 id = AddressIds.REGISTRY_FACTORY;
        address newAddress = address(registryFactory);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getRegistryFactory(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setRegistryFactory(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getRegistryFactory(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setRegistryFactory(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getRegistryFactory(), newAddress);
    }

    function test__set_allocator_factory() public {
        bytes32 id = AddressIds.ALLOCATOR_FACTORY;
        address newAddress = user;

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getAllocatorFactory(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setAllocatorFactory(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getAllocatorFactory(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setAllocatorFactory(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getAllocatorFactory(), newAddress);
    }

    function test__set_accountant_factory() public {
        bytes32 id = AddressIds.ACCOUNTANT_FACTORY;
        address newAddress = address(registryFactory);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getAccountantFactory(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setAccountantFactory(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getAccountantFactory(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setAccountantFactory(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getAccountantFactory(), newAddress);
    }

    function test__set_role_manager_factory() public {
        bytes32 id = AddressIds.ROLE_MANAGER_FACTORY;
        address newAddress = address(0x123);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getRoleManagerFactory(), ZERO_ADDRESS);

        vm.prank(user);
        vm.expectRevert("!governance");
        addressProvider.setRoleManagerFactory(newAddress);

        assertEq(addressProvider.getAddress(id), ZERO_ADDRESS);
        assertEq(addressProvider.getRoleManagerFactory(), ZERO_ADDRESS);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true, address(addressProvider));
        emit UpdatedAddress(id, ZERO_ADDRESS, newAddress);
        addressProvider.setRoleManagerFactory(newAddress);

        assertEq(addressProvider.getAddress(id), newAddress);
        assertEq(addressProvider.getRoleManagerFactory(), newAddress);
    }

    function test_gov_transfers_ownership() public {
        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), ZERO_ADDRESS);

        vm.prank(daddy);
        addressProvider.transferGovernance(management);

        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), management);

        vm.prank(management);
        addressProvider.acceptGovernance();

        assertEq(addressProvider.governance(), management);
        assertEq(addressProvider.pendingGovernance(), ZERO_ADDRESS);
    }

    function test_gov_transfers_ownership_gov_cant_accept() public {
        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), ZERO_ADDRESS);

        vm.prank(daddy);
        addressProvider.transferGovernance(management);

        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), management);

        vm.prank(daddy);
        vm.expectRevert("!pending governance");
        addressProvider.acceptGovernance();

        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), management);
    }

    function test_random_transfers_ownership__fails() public {
        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), ZERO_ADDRESS);

        vm.prank(management);
        vm.expectRevert("!governance");
        addressProvider.transferGovernance(management);

        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), ZERO_ADDRESS);
    }

    function test_gov_transfers_ownership__can_change_pending() public {
        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), ZERO_ADDRESS);

        vm.prank(daddy);
        addressProvider.transferGovernance(management);

        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), management);

        vm.prank(daddy);
        addressProvider.transferGovernance(user);

        assertEq(addressProvider.governance(), daddy);
        assertEq(addressProvider.pendingGovernance(), user);

        vm.prank(management);
        vm.expectRevert("!pending governance");
        addressProvider.acceptGovernance();

        vm.prank(user);
        addressProvider.acceptGovernance();

        assertEq(addressProvider.governance(), user);
        assertEq(addressProvider.pendingGovernance(), ZERO_ADDRESS);
    }

    event UpdatedAddress(
        bytes32 indexed addressId,
        address indexed oldAddress,
        address indexed newAddress
    );
}

library AddressIds {
    bytes32 constant ROUTER = keccak256("Router");
    bytes32 constant KEEPER = keccak256("Keeper");
    bytes32 constant APR_ORACLE = keccak256("APR Oracle");
    bytes32 constant RELEASE_REGISTRY = keccak256("Release Registry");
    bytes32 constant BASE_FEE_PROVIDER = keccak256("Base Fee Provider");
    bytes32 constant COMMON_REPORT_TRIGGER = keccak256("Common Report Trigger");
    bytes32 constant AUCTION_FACTORY = keccak256("Auction Factory");
    bytes32 constant SPLITTER_FACTORY = keccak256("Splitter Factory");
    bytes32 constant REGISTRY_FACTORY = keccak256("Registry Factory");
    bytes32 constant ALLOCATOR_FACTORY = keccak256("Allocator Factory");
    bytes32 constant ACCOUNTANT_FACTORY = keccak256("Accountant Factory");
    bytes32 constant ROLE_MANAGER_FACTORY = keccak256("Role Manager Factory");
}
