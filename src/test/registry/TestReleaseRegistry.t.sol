// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, Registry, ReleaseRegistry, IVaultFactory, IVault, MockStrategy} from "../utils/Setup.sol";
import {MockFactory} from "../../Mocks/MockFactory.sol";

contract TestReleaseRegistry is Setup {
    event NewRelease(
        uint256 indexed releaseId,
        address indexed factory,
        string apiVersion
    );
    event GovernanceTransferred(
        address indexed previousGovernance,
        address indexed newGovernance
    );

    function setUp() public override {
        super.setUp();
    }

    function test__deployment() public {
        assertEq(releaseRegistry.governance(), daddy);
        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));
        assertEq(releaseRegistry.releaseTargets("3.0.3"), 0);
    }

    function test_new_release() public {
        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));

        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewRelease(0, address(vaultFactory), vaultFactory.apiVersion());
        releaseRegistry.newRelease(address(vaultFactory));

        assertEq(releaseRegistry.numReleases(), 1);
        assertEq(releaseRegistry.factories(0), address(vaultFactory));
        assertEq(releaseRegistry.releaseTargets(vaultFactory.apiVersion()), 0);
        assertEq(releaseRegistry.latestFactory(), address(vaultFactory));
        assertEq(releaseRegistry.latestRelease(), vaultFactory.apiVersion());

        string memory new_api = "4.3.2";
        // Deploy a new mock factory with a different api
        MockFactory new_factory = new MockFactory(new_api);

        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewRelease(1, address(new_factory), new_api);
        releaseRegistry.newRelease(address(new_factory));

        assertEq(releaseRegistry.numReleases(), 2);
        assertEq(releaseRegistry.factories(1), address(new_factory));
        assertEq(releaseRegistry.releaseTargets(new_api), 1);
        assertEq(releaseRegistry.latestFactory(), address(new_factory));
        assertEq(releaseRegistry.latestRelease(), new_api);

        // make sure the first factory is still returning
        assertEq(releaseRegistry.factories(0), address(vaultFactory));
        assertEq(releaseRegistry.releaseTargets(vaultFactory.apiVersion()), 0);
    }

    function test_access() public {
        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));

        // only daddy should be able to set a new release
        vm.prank(user);
        vm.expectRevert();
        releaseRegistry.newRelease(address(vaultFactory));

        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));

        vm.prank(daddy);
        releaseRegistry.newRelease(address(vaultFactory));

        assertEq(releaseRegistry.numReleases(), 1);
        assertEq(releaseRegistry.factories(0), address(vaultFactory));
    }

    function test__add_same_factory() public {
        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));

        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewRelease(0, address(vaultFactory), vaultFactory.apiVersion());
        releaseRegistry.newRelease(address(vaultFactory));

        assertEq(releaseRegistry.numReleases(), 1);
        assertEq(releaseRegistry.factories(0), address(vaultFactory));
        assertEq(releaseRegistry.latestFactory(), address(vaultFactory));
        assertEq(releaseRegistry.latestRelease(), vaultFactory.apiVersion());

        vm.prank(daddy);
        vm.expectRevert("ReleaseRegistry: same api version");
        releaseRegistry.newRelease(address(vaultFactory));

        assertEq(releaseRegistry.numReleases(), 1);
    }

    function test__transfer_governance() public {
        assertEq(releaseRegistry.governance(), daddy);

        vm.prank(daddy);
        vm.expectRevert("ZERO ADDRESS");
        releaseRegistry.transferGovernance(address(0));

        assertEq(releaseRegistry.governance(), daddy);

        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit GovernanceTransferred(daddy, user);
        releaseRegistry.transferGovernance(user);

        assertEq(releaseRegistry.governance(), user);
    }
}
