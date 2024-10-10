// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, Registry, ReleaseRegistry, IVaultFactory, IVault, MockStrategy} from "../utils/Setup.sol";
import {MockFactory} from "../../mocks/MockFactory.sol";

contract TestRegistry is Setup {
    event NewEndorsedVault(
        address indexed vault,
        address indexed asset,
        uint256 releaseVersion,
        uint256 vaultType
    );

    /// @notice Emitted when a vault is removed.
    event RemovedVault(
        address indexed vault,
        address indexed asset,
        uint256 releaseVersion,
        uint256 vaultType
    );

    /// @notice Emitted when a vault is tagged with a string.
    event VaultTagged(address indexed vault);

    /// @notice Emitted when gov adds ore removes a `tagger`.
    event UpdateTagger(address indexed account, bool status);

    /// @notice Emitted when gov adds ore removes a `endorser`.
    event UpdateEndorser(address indexed account, bool status);

    MockStrategy public strategy;

    function setUp() public override {
        super.setUp();
        strategy = new MockStrategy(address(asset), "3.0.3");
    }

    function test__set_up() public {
        assertEq(registry.governance(), daddy);
        assertEq(registry.releaseRegistry(), address(releaseRegistry));
        assertEq(registry.numAssets(), 0);
        assertEq(registry.numEndorsedVaults(address(asset)), 0);
    }

    function test__deploy_new_vault() public {
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        vm.prank(daddy);
        vm.expectEmit(false, true, false, true, address(registry));
        emit NewEndorsedVault(
            address(0),
            address(asset),
            0,
            registry.MULTI_STRATEGY_TYPE()
        );
        address newVaultAddress = registry.newEndorsedVault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK
        );

        IVault newVault = IVault(newVaultAddress);

        assertEq(newVault.asset(), address(asset));
        assertEq(newVault.name(), name);
        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.role_manager(), daddy);
        assertEq(newVault.profitMaxUnlockTime(), WEEK);

        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(newVault)
        );

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(newVault));

        (
            address vaultAsset,
            uint96 releaseVersion,
            uint64 vaultType,
            uint128 deploymentTimestamp,
            ,

        ) = registry.vaultInfo(address(newVault));
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, registry.MULTI_STRATEGY_TYPE());
        assertEq(deploymentTimestamp, block.timestamp);
    }

    function test__endorse_deployed_vault() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        // Deploy a new vault
        vm.prank(daddy);
        address newVaultAddress = vaultFactory.deploy_new_vault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK
        );
        IVault newVault = IVault(newVaultAddress);

        uint256 deploymentTimestamp = block.timestamp;

        // Endorse vault
        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewEndorsedVault(
            address(newVault),
            address(asset),
            0,
            registry.MULTI_STRATEGY_TYPE()
        );
        registry.endorseVault(
            address(newVault),
            0,
            registry.MULTI_STRATEGY_TYPE(),
            deploymentTimestamp
        );

        // Make sure it was endorsed correctly
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(newVault)
        );

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(newVault));

        (
            address vaultAsset,
            uint96 releaseVersion,
            uint64 vaultType,
            uint128 vaultDeploymentTimestamp,
            ,

        ) = registry.vaultInfo(address(newVault));
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, registry.MULTI_STRATEGY_TYPE());
        assertEq(vaultDeploymentTimestamp, deploymentTimestamp);
    }

    function test__endorse_deployed_strategy() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        // Endorse the strategy
        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewEndorsedVault(
            address(strategy),
            address(asset),
            0,
            registry.SINGLE_STRATEGY_TYPE()
        );
        registry.endorseVault(address(strategy), 0, 2, block.timestamp);

        // Make sure it was endorsed correctly
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(strategy)
        );

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(strategy));

        (
            address vaultAsset,
            uint96 releaseVersion,
            uint64 vaultType,
            uint128 deploymentTimestamp,
            ,

        ) = registry.vaultInfo(address(strategy));
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, registry.SINGLE_STRATEGY_TYPE());
        assertEq(deploymentTimestamp, block.timestamp);
    }

    function test__endorse_deployed_vault__default_values() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        // Deploy a new vault
        vm.prank(daddy);
        address newVaultAddress = vaultFactory.deploy_new_vault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK
        );
        IVault newVault = IVault(newVaultAddress);

        // Endorse vault with default values
        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewEndorsedVault(
            address(newVault),
            address(asset),
            0,
            registry.MULTI_STRATEGY_TYPE()
        );
        registry.endorseMultiStrategyVault(address(newVault));

        // Make sure it was endorsed correctly
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(newVault)
        );

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(newVault));

        (
            address vaultAsset,
            uint96 releaseVersion,
            uint64 vaultType,
            uint128 deploymentTimestamp,
            ,

        ) = registry.vaultInfo(address(newVault));
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, registry.MULTI_STRATEGY_TYPE());
        assertEq(deploymentTimestamp, 0);
    }

    function test__endorse_deployed_strategy__default_values() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        // Endorse the strategy with default values
        vm.prank(daddy);
        vm.expectEmit(true, true, false, true);
        emit NewEndorsedVault(
            address(strategy),
            address(asset),
            0,
            registry.SINGLE_STRATEGY_TYPE()
        );
        registry.endorseSingleStrategyVault(address(strategy));

        // Make sure it was endorsed correctly
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(strategy)
        );

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(strategy));

        (
            address vaultAsset,
            uint96 releaseVersion,
            uint64 vaultType,
            uint128 deploymentTimestamp,
            ,

        ) = registry.vaultInfo(address(strategy));
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, registry.SINGLE_STRATEGY_TYPE());
        assertEq(deploymentTimestamp, 0);
    }

    function test__deploy_vault_with_new_release() public {
        // Add a mock factory for version release 1
        MockFactory mockFactory = new MockFactory("2.0.0");
        MockStrategy mockStrategy = new MockStrategy(address(asset), "2.0.0");
        vm.prank(daddy);
        releaseRegistry.newRelease(address(mockFactory), address(mockStrategy));

        assertEq(releaseRegistry.numReleases(), 1);

        // Add the factory as the second release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 2);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        // Deploy a new vault with the latest release
        vm.prank(daddy);
        vm.expectEmit(false, true, false, true, address(registry));
        emit NewEndorsedVault(
            address(0),
            address(asset),
            1,
            registry.MULTI_STRATEGY_TYPE()
        );
        address newVaultAddress = registry.newEndorsedVault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK
        );
        IVault newVault = IVault(newVaultAddress);

        assertEq(newVault.asset(), address(asset));
        assertEq(newVault.name(), name);
        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.role_manager(), daddy);
        assertEq(newVault.profitMaxUnlockTime(), WEEK);

        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(newVault)
        );

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(newVault));

        (
            address vaultAsset,
            uint96 releaseVersion,
            uint64 vaultType,
            uint128 deploymentTimestamp,
            ,

        ) = registry.vaultInfo(address(newVault));
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 1);
        assertEq(vaultType, registry.MULTI_STRATEGY_TYPE());
        assertEq(deploymentTimestamp, block.timestamp);
    }

    function test__deploy_vault_with_old_release() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        // Add a mock factory for version release 2
        MockFactory mockFactory = new MockFactory("2.0.0");
        MockStrategy mockStrategy = new MockStrategy(address(asset), "2.0.0");
        vm.prank(daddy);
        releaseRegistry.newRelease(address(mockFactory), address(mockStrategy));

        assertEq(releaseRegistry.numReleases(), 2);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        // Deploy a new vault with the old release
        vm.prank(daddy);
        vm.expectEmit(false, true, false, true, address(registry));
        emit NewEndorsedVault(address(0), address(asset), 0, 1);
        address newVaultAddress = registry.newEndorsedVault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK,
            1
        );
        IVault newVault = IVault(newVaultAddress);

        assertEq(newVault.asset(), address(asset));
        assertEq(newVault.name(), name);
        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.role_manager(), daddy);
        assertEq(newVault.profitMaxUnlockTime(), WEEK);

        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(newVault)
        );

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(newVault));

        (
            address vaultAsset,
            uint96 releaseVersion,
            uint64 vaultType,
            uint128 deploymentTimestamp,
            ,

        ) = registry.vaultInfo(address(newVault));
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, registry.MULTI_STRATEGY_TYPE());
        assertEq(deploymentTimestamp, block.timestamp);
    }

    function test__endorse_deployed_vault_wrong_api__reverts() public {
        // Add a mock factory for version release 1
        MockFactory mockFactory = new MockFactory("6.9");
        MockStrategy mockStrategy = new MockStrategy(address(asset), "6.9");
        addNewRelease(
            releaseRegistry,
            IVaultFactory(address(mockFactory)),
            address(mockStrategy),
            daddy
        );

        assertEq(releaseRegistry.numReleases(), 1);

        // Set the factory as the second release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 2);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        // Deploy a new vault
        vm.prank(daddy);
        address newVaultAddress = vaultFactory.deploy_new_vault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK
        );
        IVault newVault = IVault(newVaultAddress);

        // Endorse vault with incorrect api version
        vm.prank(daddy);
        vm.expectRevert("Wrong API Version");
        registry.endorseVault(address(newVault), 1, 1, block.timestamp);

        // Endorse vault with correct api version
        vm.prank(daddy);
        registry.endorseVault(address(newVault), 0, 1, block.timestamp);
    }

    function test__endorse_strategy_wrong_api__reverts() public {
        // Add a mock factory for version release 1
        MockFactory mockFactory = new MockFactory("6.9");
        MockStrategy mockStrategy = new MockStrategy(address(asset), "6.9");
        addNewRelease(
            releaseRegistry,
            IVaultFactory(address(mockFactory)),
            address(mockStrategy),
            daddy
        );

        assertEq(releaseRegistry.numReleases(), 1);

        // Set the factory as the second release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 2);

        // Endorse strategy with incorrect api version
        vm.prank(daddy);
        vm.expectRevert("Wrong API Version");
        registry.endorseVault(address(strategy), 1, 2, 0);

        // Endorse strategy with correct api version
        vm.prank(daddy);
        registry.endorseVault(address(strategy), 0, 2, 0);
    }

    function test__remove_vault() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        // Deploy a new vault
        vm.prank(daddy);
        address newVaultAddress = registry.newEndorsedVault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK
        );
        IVault newVault = IVault(newVaultAddress);

        // Make sure it was endorsed correctly
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(newVault)
        );

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(newVault));

        (
            address vaultAsset,
            uint96 releaseVersion,
            uint64 vaultType,
            uint128 deploymentTimestamp,
            uint64 index,
            string memory tag
        ) = registry.vaultInfo(address(newVault));
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, registry.MULTI_STRATEGY_TYPE());
        assertEq(deploymentTimestamp, block.timestamp);
        assertEq(index, 0);
        assertEq(tag, "");

        // Remove the vault
        vm.prank(daddy);
        registry.removeVault(address(newVault));

        // Make sure it was removed
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 0);
        assertEq(registry.getEndorsedVaults(address(asset)).length, 0);

        allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 0);

        (
            vaultAsset,
            releaseVersion,
            vaultType,
            deploymentTimestamp,
            index,
            tag
        ) = registry.vaultInfo(address(newVault));
        assertEq(vaultAsset, address(0));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, 0);
        assertEq(deploymentTimestamp, 0);
        assertEq(index, 0);
        assertEq(tag, "");
    }

    function test__remove_vault__two_vaults() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        // Deploy two new vaults
        vm.startPrank(daddy);
        address newVaultAddress = registry.newEndorsedVault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK
        );
        IVault newVault = IVault(newVaultAddress);

        address secondVaultAddress = registry.newEndorsedVault(
            address(asset),
            "second Vault",
            "sec",
            daddy,
            WEEK
        );
        IVault secondVault = IVault(secondVaultAddress);
        vm.stopPrank();

        // Make sure they are endorsed correctly
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 2);

        address[] memory endorsedVaults = registry.getEndorsedVaults(
            address(asset)
        );
        assertEq(endorsedVaults[0], address(newVault));
        assertEq(endorsedVaults[1], address(secondVault));

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 2);
        assertEq(allVaults[0], address(newVault));
        assertEq(allVaults[1], address(secondVault));

        // Remove the first vault
        vm.prank(daddy);
        registry.removeVault(address(newVault));

        // Make sure the second is still endorsed
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(secondVault)
        );

        allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(secondVault));

        (address vaultAsset, , , , , ) = registry.vaultInfo(address(newVault));
        assertEq(vaultAsset, address(0));

        (vaultAsset, , , , , ) = registry.vaultInfo(address(secondVault));
        assertEq(vaultAsset, address(asset));
    }

    function test__remove_strategy() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        // Endorse the strategy
        vm.prank(daddy);
        registry.endorseSingleStrategyVault(address(strategy));

        // Make sure it was endorsed correctly
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(strategy)
        );

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(strategy));

        (
            address vaultAsset,
            uint96 releaseVersion,
            uint64 vaultType,
            ,
            ,

        ) = registry.vaultInfo(address(strategy));
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, registry.SINGLE_STRATEGY_TYPE());

        // Remove the strategy
        vm.prank(daddy);
        registry.removeVault(address(strategy));

        // Make sure it was removed
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 0);
        assertEq(registry.getEndorsedVaults(address(asset)).length, 0);

        allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 0);

        (vaultAsset, releaseVersion, vaultType, , , ) = registry.vaultInfo(
            address(strategy)
        );
        assertEq(vaultAsset, address(0));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, 0);
    }

    function test__remove_strategy__two_strategies() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        vm.prank(daddy);
        registry.endorseSingleStrategyVault(address(strategy));

        MockStrategy secondStrategy = new MockStrategy(address(asset), "3.0.3");
        vm.prank(daddy);
        registry.endorseSingleStrategyVault(address(secondStrategy));

        // Make sure they are endorsed correctly
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 2);

        address[] memory endorsedVaults = registry.getEndorsedVaults(
            address(asset)
        );
        assertEq(endorsedVaults[0], address(strategy));
        assertEq(endorsedVaults[1], address(secondStrategy));

        address[] memory allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 2);
        assertEq(allVaults[0], address(strategy));
        assertEq(allVaults[1], address(secondStrategy));

        // Remove the first strategy
        vm.prank(daddy);
        registry.removeVault(address(strategy));

        // Make sure the second is still endorsed
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(secondStrategy)
        );

        allVaults = registry.getAllEndorsedVaults()[0];
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(secondStrategy));

        (address vaultAsset, , , , , ) = registry.vaultInfo(address(strategy));
        assertEq(vaultAsset, address(0));

        uint96 releaseVersion;
        uint64 vaultType;
        (vaultAsset, releaseVersion, vaultType, , , ) = registry.vaultInfo(
            address(secondStrategy)
        );
        assertEq(vaultAsset, address(asset));
        assertEq(releaseVersion, 0);
        assertEq(vaultType, registry.SINGLE_STRATEGY_TYPE());
    }

    function test__remove_asset() public {
        // Add the factory as the first release
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        vm.prank(daddy);
        registry.endorseSingleStrategyVault(address(strategy));

        // Make sure it was endorsed correctly
        assertEq(registry.numAssets(), 1);
        assertEq(registry.getAssets()[0], address(asset));
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(
            registry.getEndorsedVaults(address(asset))[0],
            address(strategy)
        );

        // Should not be able to remove the asset
        vm.prank(daddy);
        vm.expectRevert("still in use");
        registry.removeAsset(address(asset), 0);

        // Remove the strategy
        vm.prank(daddy);
        registry.removeVault(address(strategy));

        vm.prank(daddy);
        registry.removeAsset(address(asset), 0);

        assertEq(registry.numAssets(), 0);
        assertEq(registry.getAssets().length, 0);
        assertFalse(registry.assetIsUsed(address(asset)));
    }

    function test__tag_vault() public {
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        assertEq(releaseRegistry.numReleases(), 1);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        // Deploy a new vault
        vm.prank(daddy);
        address newVaultAddress = registry.newEndorsedVault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK
        );
        IVault newVault = IVault(newVaultAddress);

        // Make sure it is endorsed but not tagged.
        (address vaultAsset, , , , , string memory vaultTag) = registry
            .vaultInfo(address(newVault));
        assertEq(vaultAsset, address(asset));
        assertEq(vaultTag, "");

        string memory tag = "Test Tag";

        vm.prank(daddy);
        vm.expectEmit(true, false, false, true);
        emit VaultTagged(address(newVault));
        registry.tagVault(address(newVault), tag);

        (vaultAsset, , , , , vaultTag) = registry.vaultInfo(address(newVault));
        assertEq(vaultAsset, address(asset));
        assertEq(vaultTag, tag);

        // Try to tag an un endorsed vault
        vm.prank(daddy);
        vm.expectRevert("!Endorsed");
        registry.tagVault(address(strategy), tag);

        // Endorse the strategy then tag it.
        vm.prank(daddy);
        registry.endorseSingleStrategyVault(address(strategy));

        (vaultAsset, , , , , vaultTag) = registry.vaultInfo(address(strategy));
        assertEq(vaultAsset, address(asset));
        assertEq(vaultTag, "");

        vm.prank(daddy);
        vm.expectEmit(true, false, false, true);
        emit VaultTagged(address(strategy));
        registry.tagVault(address(strategy), tag);

        (vaultAsset, , , , , vaultTag) = registry.vaultInfo(address(strategy));
        assertEq(vaultAsset, address(asset));
        assertEq(vaultTag, tag);
    }

    function test__access() public {
        addNewRelease(releaseRegistry, vaultFactory, address(strategy), daddy);

        string memory name = "New vaults";
        string memory symbol = "yvTest";

        // Cant deploy a vault through registry
        vm.prank(user);
        vm.expectRevert("!endorser");
        registry.newEndorsedVault(address(asset), name, symbol, daddy, WEEK);

        // Deploy a new vault
        vm.prank(daddy);
        address newVaultAddress = vaultFactory.deploy_new_vault(
            address(asset),
            name,
            symbol,
            daddy,
            WEEK
        );
        IVault newVault = IVault(newVaultAddress);

        // Cant endorse a vault
        vm.prank(user);
        vm.expectRevert("!endorser");
        registry.endorseVault(address(newVault), 0, 1, block.timestamp);

        // cant endorse vault with default values
        vm.prank(user);
        vm.expectRevert("!endorser");
        registry.endorseMultiStrategyVault(address(newVault));

        // cant endorse strategy with default values
        vm.prank(user);
        vm.expectRevert("!endorser");
        registry.endorseSingleStrategyVault(address(strategy));

        // cant remove vault or asset
        vm.prank(user);
        vm.expectRevert("!endorser");
        registry.removeVault(address(newVault));

        vm.prank(user);
        vm.expectRevert("!endorser");
        registry.removeAsset(address(asset), 0);

        // Make user an endorser
        vm.prank(user);
        vm.expectRevert("!governance");
        registry.setEndorser(user, true);

        vm.prank(daddy);
        registry.setEndorser(user, true);

        assertTrue(registry.endorsers(user));

        vm.prank(user);
        registry.endorseVault(address(newVault), 0, 1, block.timestamp);

        assertTrue(registry.isEndorsed(address(newVault)));

        vm.prank(user);
        vm.expectRevert("!tagger");
        registry.tagVault(address(strategy), "tag");

        // Make user a tagger
        vm.prank(user);
        vm.expectRevert("!governance");
        registry.setTagger(user, true);

        vm.prank(daddy);
        registry.setTagger(user, true);

        assertTrue(registry.taggers(user));

        // Tag the vault
        vm.prank(user);
        registry.tagVault(address(newVault), "tag");

        (, , , , , string memory tag) = registry.vaultInfo(address(newVault));
        assertEq(tag, "tag");

        // User should be able to remove vaults and assets now too
        vm.prank(user);
        registry.removeVault(address(newVault));

        assertFalse(registry.isEndorsed(address(newVault)));

        assertEq(registry.numAssets(), 1);

        vm.prank(user);
        registry.removeAsset(address(asset), 0);

        assertEq(registry.numAssets(), 0);

        // cant transfer governance
        vm.prank(user);
        vm.expectRevert("!governance");
        registry.transferGovernance(user);
    }

    function test__transfer_governance() public {
        assertEq(registry.governance(), daddy);

        vm.prank(daddy);
        vm.expectRevert("ZERO ADDRESS");
        registry.transferGovernance(address(0));

        assertEq(registry.governance(), daddy);

        vm.prank(daddy);
        registry.transferGovernance(user);

        assertEq(registry.governance(), user);
    }

    // Helper function to add a new release
    function addNewRelease(
        ReleaseRegistry _releaseRegistry,
        IVaultFactory _factory,
        address _tokenizedStrategy,
        address _owner
    ) internal {
        vm.prank(_owner);
        _releaseRegistry.newRelease(address(_factory), _tokenizedStrategy);
    }
}
