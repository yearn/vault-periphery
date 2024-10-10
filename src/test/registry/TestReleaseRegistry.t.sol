// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, Registry, ReleaseRegistry, IVaultFactory, IVault, MockStrategy} from "../utils/Setup.sol";
import {MockFactory} from "../../mocks/MockFactory.sol";

contract TestReleaseRegistry is Setup {
    event NewRelease(
        uint256 indexed releaseId,
        address indexed factory,
        address indexed tokenizedStrategy,
        string apiVersion
    );
    event GovernanceTransferred(
        address indexed previousGovernance,
        address indexed newGovernance
    );

    address public tokenizedStrategy;

    function setUp() public override {
        super.setUp();
        tokenizedStrategy = address(
            new MockStrategy(address(asset), vaultFactory.apiVersion())
        );
    }

    function test__deployment() public {
        assertEq(releaseRegistry.governance(), daddy);
        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));
        assertEq(releaseRegistry.tokenizedStrategies(0), address(0));
        assertEq(releaseRegistry.releaseTargets("3.0.3"), 0);
    }

    function test_new_release() public {
        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));
        assertEq(releaseRegistry.tokenizedStrategies(0), address(0));
        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewRelease(
            0,
            address(vaultFactory),
            tokenizedStrategy,
            vaultFactory.apiVersion()
        );
        releaseRegistry.newRelease(address(vaultFactory), tokenizedStrategy);

        assertEq(releaseRegistry.numReleases(), 1);
        assertEq(releaseRegistry.factories(0), address(vaultFactory));
        assertEq(releaseRegistry.tokenizedStrategies(0), tokenizedStrategy);
        assertEq(releaseRegistry.releaseTargets(vaultFactory.apiVersion()), 0);
        assertEq(releaseRegistry.latestFactory(), address(vaultFactory));
        assertEq(releaseRegistry.latestRelease(), vaultFactory.apiVersion());
        assertEq(releaseRegistry.latestTokenizedStrategy(), tokenizedStrategy);
        string memory new_api = "4.3.2";
        // Deploy a new mock factory with a different api
        MockFactory new_factory = new MockFactory(new_api);
        MockStrategy new_strategy = new MockStrategy(address(asset), new_api);

        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewRelease(
            1,
            address(new_factory),
            address(new_strategy),
            new_api
        );
        releaseRegistry.newRelease(address(new_factory), address(new_strategy));

        assertEq(releaseRegistry.numReleases(), 2);
        assertEq(releaseRegistry.factories(1), address(new_factory));
        assertEq(releaseRegistry.tokenizedStrategies(1), address(new_strategy));
        assertEq(releaseRegistry.releaseTargets(new_api), 1);
        assertEq(releaseRegistry.latestFactory(), address(new_factory));
        assertEq(releaseRegistry.latestRelease(), new_api);
        assertEq(
            releaseRegistry.latestTokenizedStrategy(),
            address(new_strategy)
        );
        // make sure the first factory is still returning
        assertEq(releaseRegistry.factories(0), address(vaultFactory));
        assertEq(releaseRegistry.releaseTargets(vaultFactory.apiVersion()), 0);
        assertEq(releaseRegistry.tokenizedStrategies(0), tokenizedStrategy);
    }

    function test_access() public {
        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));

        // only daddy should be able to set a new release
        vm.prank(user);
        vm.expectRevert();
        releaseRegistry.newRelease(
            address(vaultFactory),
            address(tokenizedStrategy)
        );

        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));
        assertEq(releaseRegistry.tokenizedStrategies(0), address(0));

        vm.prank(daddy);
        releaseRegistry.newRelease(
            address(vaultFactory),
            address(tokenizedStrategy)
        );

        assertEq(releaseRegistry.numReleases(), 1);
        assertEq(releaseRegistry.factories(0), address(vaultFactory));
        assertEq(
            releaseRegistry.tokenizedStrategies(0),
            address(tokenizedStrategy)
        );
    }

    function test__add_same_factory() public {
        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));

        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewRelease(
            0,
            address(vaultFactory),
            tokenizedStrategy,
            vaultFactory.apiVersion()
        );
        releaseRegistry.newRelease(address(vaultFactory), tokenizedStrategy);

        assertEq(releaseRegistry.numReleases(), 1);
        assertEq(releaseRegistry.factories(0), address(vaultFactory));
        assertEq(releaseRegistry.latestFactory(), address(vaultFactory));
        assertEq(releaseRegistry.latestRelease(), vaultFactory.apiVersion());
        assertEq(releaseRegistry.tokenizedStrategies(0), tokenizedStrategy);
        assertEq(releaseRegistry.latestTokenizedStrategy(), tokenizedStrategy);

        vm.prank(daddy);
        vm.expectRevert("ReleaseRegistry: same api version");
        releaseRegistry.newRelease(address(vaultFactory), tokenizedStrategy);

        assertEq(releaseRegistry.numReleases(), 1);
    }

    function test_revert_mismatched_api_versions() public {
        // Deploy a new vault factory with a different API version
        MockFactory newVaultFactory = new MockFactory("2.0.0");

        vm.prank(daddy);
        vm.expectRevert("ReleaseRegistry: api version mismatch");
        releaseRegistry.newRelease(address(newVaultFactory), tokenizedStrategy);

        // Ensure no new release was added
        assertEq(releaseRegistry.numReleases(), 0);
        assertEq(releaseRegistry.factories(0), address(0));
        assertEq(releaseRegistry.tokenizedStrategies(0), address(0));
    }

    function test__transfer_governance_two_step() public {
        address newGovernance = user;

        // Initial state
        assertEq(releaseRegistry.governance(), daddy);
        assertEq(releaseRegistry.pendingGovernance(), address(0));

        // Step 1: Current governance initiates transfer
        vm.prank(daddy);
        releaseRegistry.transferGovernance(newGovernance);

        // Check intermediate state
        assertEq(releaseRegistry.governance(), daddy);
        assertEq(releaseRegistry.pendingGovernance(), newGovernance);

        // Attempt to accept from wrong address
        vm.prank(daddy);
        vm.expectRevert("!pending governance");
        releaseRegistry.acceptGovernance();

        // Step 2: New governance accepts transfer
        vm.prank(newGovernance);
        releaseRegistry.acceptGovernance();

        // Check final state
        assertEq(releaseRegistry.governance(), newGovernance);
        assertEq(releaseRegistry.pendingGovernance(), address(0));
    }
}
