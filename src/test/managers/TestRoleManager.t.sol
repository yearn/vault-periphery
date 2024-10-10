// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, RoleManager, IVault, Roles, MockStrategy, DebtAllocator} from "../utils/Setup.sol";

contract TestRoleManager is Setup {
    error AlreadyDeployed(address _vault);

    event RoleSet(address indexed account, uint256 role);

    event AddedNewVault(
        address indexed vault,
        address indexed debtAllocator,
        uint256 category
    );

    /// @notice Emitted when a vaults debt allocator is updated.
    event UpdateDebtAllocator(
        address indexed vault,
        address indexed debtAllocator
    );

    /// @notice Emitted when a new address is set for a position.
    event UpdatePositionHolder(
        bytes32 indexed position,
        address indexed newAddress
    );

    /// @notice Emitted when a vault is removed.
    event RemovedVault(address indexed vault);

    /// @notice Emitted when a new set of roles is set for a position
    event UpdatePositionRoles(bytes32 indexed position, uint256 newRoles);

    /// @notice Emitted when the defaultProfitMaxUnlock variable is updated.
    event UpdateDefaultProfitMaxUnlock(uint256 newDefaultProfitMaxUnlock);

    IVault public vault;
    MockStrategy public strategy;

    uint256 constant daddy_roles = Roles.ALL;
    uint256 constant brain_roles =
        Roles.REPORTING_MANAGER |
            Roles.DEBT_MANAGER |
            Roles.QUEUE_MANAGER |
            Roles.DEPOSIT_LIMIT_MANAGER |
            Roles.DEBT_PURCHASER |
            Roles.PROFIT_UNLOCK_MANAGER;
    uint256 constant keeper_roles = Roles.REPORTING_MANAGER;
    uint256 constant debt_allocator_roles =
        Roles.REPORTING_MANAGER | Roles.DEBT_MANAGER;

    function setUp() public virtual override {
        super.setUp();
        vault = createVault(
            address(asset),
            daddy,
            MAX_INT,
            WEEK,
            "Test Vault",
            "tvTEST"
        );
        strategy = createStrategy(address(asset));

        vm.prank(daddy);
        releaseRegistry.newRelease(address(vaultFactory));
    }

    function test_role_manager_setup() public {
        assertEq(roleManager.chad(), daddy);
        assertEq(roleManager.getAllVaults().length, 0);
        assertEq(
            roleManager.getVault(address(asset), vault.apiVersion(), 1),
            address(0)
        );
        assertEq(roleManager.getGovernance(), daddy);
        assertEq(roleManager.getManagement(), brain);
        assertEq(roleManager.getKeeper(), address(keeper));
        assertEq(roleManager.getRegistry(), address(registry));
        assertEq(roleManager.getAccountant(), address(accountant));
        assertEq(roleManager.getDebtAllocator(), address(debtAllocator));
        assertFalse(roleManager.isVaultsRoleManager(address(vault)));
        assertEq(roleManager.getDebtAllocator(address(vault)), address(0));
        assertEq(roleManager.getCategory(address(vault)), 0);

        // Check registry too.
        assertEq(address(registry.releaseRegistry()), address(releaseRegistry));
        assertEq(registry.numAssets(), 0);
        assertEq(registry.numEndorsedVaults(address(asset)), 0);
    }

    function test__positions() public {
        assertEq(roleManager.getGovernance(), daddy);
        assertEq(roleManager.getManagement(), brain);
        assertEq(roleManager.getKeeper(), address(keeper));
        assertEq(roleManager.getRegistry(), address(registry));
        assertEq(roleManager.getAccountant(), address(accountant));
        assertEq(roleManager.getDebtAllocator(), address(debtAllocator));
        assertEq(
            roleManager.getPositionHolder(roleManager.GOVERNANCE()),
            daddy
        );
        assertEq(
            roleManager.getPositionHolder(roleManager.MANAGEMENT()),
            brain
        );
        assertEq(
            roleManager.getPositionHolder(roleManager.KEEPER()),
            address(keeper)
        );
        assertEq(
            roleManager.getPositionHolder(roleManager.REGISTRY()),
            address(registry)
        );
        assertEq(
            roleManager.getPositionHolder(roleManager.ACCOUNTANT()),
            address(accountant)
        );
        assertEq(
            roleManager.getPositionHolder(roleManager.DEBT_ALLOCATOR()),
            address(debtAllocator)
        );

        // Check roles
        assertEq(roleManager.getGovernanceRoles(), daddy_roles);
        assertEq(roleManager.getManagementRoles(), brain_roles);
        assertEq(roleManager.getKeeperRoles(), keeper_roles);
        assertEq(roleManager.getDebtAllocatorRoles(), debt_allocator_roles);
        assertEq(
            roleManager.getPositionRoles(roleManager.GOVERNANCE()),
            daddy_roles
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.MANAGEMENT()),
            brain_roles
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.KEEPER()),
            keeper_roles
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.DEBT_ALLOCATOR()),
            debt_allocator_roles
        );

        bytes32 id = keccak256("rando");
        (address holder, uint256 roles) = roleManager.getPosition(id);
        assertEq(holder, address(0));
        assertEq(roles, 0);
        assertEq(roleManager.getPositionHolder(id), address(0));
        assertEq(roleManager.getPositionRoles(id), 0);

        vm.prank(user);
        vm.expectRevert("!allowed");
        roleManager.setPositionHolder(id, user);

        bytes32[4] memory positionIds = [
            roleManager.PENDING_GOVERNANCE(),
            roleManager.MANAGEMENT(),
            roleManager.REGISTRY(),
            roleManager.ACCOUNTANT()
        ];

        address[4] memory positionHolders = [
            address(0),
            brain,
            address(registry),
            address(accountant)
        ];

        uint256[4] memory positionRoles = [0, brain_roles, 0, 0];

        uint256 new_role = 42069;

        for (uint256 i = 0; i < positionIds.length; i++) {
            (address currentHolder, uint256 currentRoles) = roleManager
                .getPosition(positionIds[i]);
            assertEq(currentHolder, positionHolders[i]);
            assertEq(currentRoles, positionRoles[i]);
            assertEq(
                roleManager.getPositionHolder(positionIds[i]),
                positionHolders[i]
            );
            assertEq(
                roleManager.getPositionRoles(positionIds[i]),
                positionRoles[i]
            );

            vm.prank(daddy);
            vm.expectEmit(true, true, true, true);
            emit UpdatePositionHolder(positionIds[i], user);
            roleManager.setPositionHolder(positionIds[i], user);

            assertEq(roleManager.getPositionHolder(positionIds[i]), user);

            vm.prank(daddy);
            vm.expectEmit(true, true, true, true);
            emit UpdatePositionRoles(positionIds[i], new_role);
            roleManager.setPositionRoles(positionIds[i], new_role);

            assertEq(roleManager.getPositionRoles(positionIds[i]), new_role);
            (address updatedHolder, uint256 updatedRoles) = roleManager
                .getPosition(positionIds[i]);
            assertEq(updatedHolder, user);
            assertEq(updatedRoles, new_role);
        }

        // Cannot update the debt allocator or keeper roles.
        bytes32 debtAllocatorId = roleManager.DEBT_ALLOCATOR();
        vm.prank(daddy);
        vm.expectRevert("cannot update");
        roleManager.setPositionRoles(debtAllocatorId, 1);

        // But can update the holder since it is not used
        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit UpdatePositionHolder(debtAllocatorId, user);
        roleManager.setPositionHolder(debtAllocatorId, user);

        bytes32 keeperId = roleManager.KEEPER();
        vm.prank(daddy);
        vm.expectRevert("cannot update");
        roleManager.setPositionRoles(keeperId, 1);

        // But can update the holder since it is not used
        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit UpdatePositionHolder(keeperId, user);
        roleManager.setPositionHolder(keeperId, user);

        id = roleManager.GOVERNANCE();
        vm.prank(daddy);
        vm.expectRevert("!two step flow");
        roleManager.setPositionHolder(id, user);

        // All positions should be changed now.
        assertEq(roleManager.getPendingGovernance(), user);
        assertEq(roleManager.getManagement(), user);
        assertEq(roleManager.getKeeper(), user);
        assertEq(roleManager.getRegistry(), user);
        assertEq(roleManager.getAccountant(), user);
        assertEq(roleManager.getDebtAllocator(), user);
        assertEq(
            roleManager.getPositionHolder(roleManager.PENDING_GOVERNANCE()),
            user
        );
        assertEq(roleManager.getPositionHolder(roleManager.MANAGEMENT()), user);
        assertEq(roleManager.getPositionHolder(roleManager.KEEPER()), user);
        assertEq(roleManager.getPositionHolder(roleManager.REGISTRY()), user);
        assertEq(roleManager.getPositionHolder(roleManager.ACCOUNTANT()), user);
        assertEq(
            roleManager.getPositionHolder(roleManager.DEBT_ALLOCATOR()),
            user
        );

        // Check roles
        assertEq(roleManager.getManagementRoles(), new_role);
        assertEq(roleManager.getKeeperRoles(), keeper_roles);
        assertEq(roleManager.getDebtAllocatorRoles(), debt_allocator_roles);
        assertEq(
            roleManager.getPositionRoles(roleManager.PENDING_GOVERNANCE()),
            new_role
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.MANAGEMENT()),
            new_role
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.KEEPER()),
            keeper_roles
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.DEBT_ALLOCATOR()),
            debt_allocator_roles
        );
    }

    function test_setters_with_zeros() public {
        bytes32 id = keccak256("rando");

        vm.prank(daddy);
        roleManager.setPositionHolder(id, address(0));

        vm.prank(daddy);
        roleManager.setPositionRoles(id, 0);

        (address holder, uint256 roles) = roleManager.getPosition(id);
        assertEq(holder, address(0));
        assertEq(roles, 0);

        vm.prank(daddy);
        address newVault = roleManager.newVault(
            address(asset),
            1,
            "testing",
            "syTest"
        );

        assertNeq(newVault, address(0));
    }

    function test_deploy_new_vault__default_values() public {
        uint256 category = 2;
        string memory name = "sdfds";
        string memory symbol = "sdf";

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category,
            name,
            symbol
        );
        IVault newVault = IVault(newVaultAddress);

        (
            address vault_asset,
            uint256 vault_category,
            address vault_debt_allocator,
            uint256 index
        ) = roleManager.vaultConfig(address(newVault));

        assertEq(vault_asset, address(asset));
        assertEq(vault_category, category);
        //assertEq(vault_debt_allocator, address(debtAllocator));
        assertEq(index, 0);
        assertEq(roleManager.getAllVaults()[0], address(newVault));
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(newVault)
        );
        assertEq(roleManager.vaults(index), address(newVault));
        assertTrue(roleManager.isVaultsRoleManager(address(newVault)));

        // Check roles
        assertEq(newVault.roles(address(roleManager)), 0);
        assertEq(newVault.roles(daddy), daddy_roles);
        assertEq(newVault.roles(brain), brain_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(
            newVault.roles(address(vault_debt_allocator)),
            debt_allocator_roles
        );
        assertEq(
            newVault.profitMaxUnlockTime(),
            roleManager.defaultProfitMaxUnlockTime()
        );

        // Check accountant
        assertEq(address(newVault.accountant()), address(accountant));
        assertTrue(accountant.vaults(address(newVault)));

        // Check deposit limit
        assertEq(newVault.maxDeposit(user), 2 ** 256 - 1);

        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.name(), name);
    }

    function test_remove_role() public {
        uint256 category = 2;
        string memory name = "sdfds";
        string memory symbol = "sdf";

        address[] memory vaults = new address[](1);

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category,
            name,
            symbol
        );
        IVault newVault = IVault(newVaultAddress);

        uint256 new_roles = daddy_roles & ~Roles.ADD_STRATEGY_MANAGER;

        vaults[0] = address(strategy);

        vm.prank(daddy);
        vm.expectRevert("vault not added");
        roleManager.removeRoles(vaults, daddy, Roles.ADD_STRATEGY_MANAGER);

        vaults[0] = address(newVault);

        vm.prank(user);
        vm.expectRevert("!allowed");
        roleManager.removeRoles(vaults, daddy, Roles.ADD_STRATEGY_MANAGER);

        vm.prank(daddy);
        roleManager.removeRoles(vaults, daddy, Roles.ADD_STRATEGY_MANAGER);

        assertEq(newVault.roles(daddy), new_roles);

        vm.prank(daddy);
        vm.expectRevert("not allowed");
        newVault.add_strategy(address(strategy));

        // Remove two roles at once
        uint256 to_remove = Roles.REVOKE_STRATEGY_MANAGER |
            Roles.FORCE_REVOKE_MANAGER;

        new_roles = new_roles & ~to_remove;

        vm.prank(daddy);
        roleManager.removeRoles(vaults, daddy, to_remove);

        assertEq(newVault.roles(daddy), new_roles);

        vm.prank(daddy);
        vm.expectRevert("not allowed");
        newVault.revoke_strategy(address(strategy));

        vm.prank(daddy);
        vm.expectRevert("not allowed");
        newVault.force_revoke_strategy(address(strategy));
    }

    function test_setters() public {
        bytes32 id = keccak256("rando");
        string memory name = "sdfds";
        string memory symbol = "sdf";

        vm.prank(daddy);
        roleManager.setPositionHolder(id, address(0));

        vm.prank(daddy);
        roleManager.setPositionRoles(id, 0);

        (address holder, uint256 roles) = roleManager.getPosition(id);
        assertEq(holder, address(0));
        assertEq(roles, 0);

        vm.prank(daddy);
        address newVault = roleManager.newVault(
            address(asset),
            1,
            name,
            symbol
        );

        assertNotEq(newVault, address(0));
    }

    function test_deploy_new_vault() public {
        uint256 category = 1;
        uint256 depositLimit = 100e18;
        string memory name = "ksjdfl";
        string memory symbol = "sdfa";

        assertEq(roleManager.getAllVaults().length, 0);
        assertEq(
            roleManager.getVault(address(asset), vault.apiVersion(), category),
            address(0)
        );
        assertEq(registry.numAssets(), 0);
        assertEq(registry.numEndorsedVaults(address(asset)), 0);

        vm.prank(user);
        vm.expectRevert("!allowed");
        roleManager.newVault(
            address(asset),
            category,
            name,
            symbol,
            depositLimit
        );

        vm.prank(daddy);
        registry.setEndorser(address(roleManager), false);
        assertTrue(!registry.endorsers(address(roleManager)));

        vm.prank(daddy);
        vm.expectRevert("!endorser");
        roleManager.newVault(
            address(asset),
            category,
            name,
            symbol,
            depositLimit
        );

        vm.prank(daddy);
        registry.setEndorser(address(roleManager), true);
        assertTrue(registry.endorsers(address(roleManager)));

        vm.prank(daddy);
        accountant.setVaultManager(address(user));

        vm.prank(daddy);
        vm.expectRevert("!vault manager");
        roleManager.newVault(
            address(asset),
            category,
            name,
            symbol,
            depositLimit
        );

        vm.prank(daddy);
        accountant.setVaultManager(address(roleManager));

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category,
            name,
            symbol,
            depositLimit
        );
        IVault newVault = IVault(newVaultAddress);

        (
            address vaultAsset,
            uint256 vaultCategory,
            address vaultDebtAllocator,
            uint256 index
        ) = roleManager.vaultConfig(address(newVault));

        assertEq(vaultAsset, address(asset));
        assertEq(vaultCategory, category);
        assertNotEq(vaultDebtAllocator, address(0));
        assertEq(index, 0);
        assertEq(roleManager.getAllVaults()[0], address(newVault));
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(newVault)
        );
        assertEq(roleManager.vaults(index), address(newVault));
        assertTrue(roleManager.isVaultsRoleManager(address(newVault)));
        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            vaultDebtAllocator
        );
        assertEq(roleManager.getCategory(address(newVault)), category);
        assertEq(registry.numAssets(), 1);
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(registry.getAllEndorsedVaults()[0][0], address(newVault));

        assertEq(newVault.roles(address(roleManager)), 0);
        assertEq(newVault.roles(daddy), daddy_roles);
        assertEq(newVault.roles(brain), brain_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(newVault.roles(vaultDebtAllocator), debt_allocator_roles);
        assertEq(newVault.profitMaxUnlockTime(), 10 days);

        assertEq(address(newVault.accountant()), address(accountant));
        assertTrue(accountant.vaults(address(newVault)));

        assertEq(newVault.maxDeposit(user), depositLimit);

        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.name(), name);
    }

    function test_deploy_new_vault__duplicate_reverts() public {
        uint256 category = 1;
        uint256 depositLimit = 100e18;
        uint256 profitUnlock = 695;
        string memory name = "ksjdfl";
        string memory symbol = "sdfa";

        vm.prank(daddy);
        registry.setEndorser(address(roleManager), true);

        vm.prank(daddy);
        accountant.setVaultManager(address(roleManager));

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category,
            name,
            symbol,
            depositLimit
        );
        IVault newVault = IVault(newVaultAddress);

        vm.prank(daddy);
        vm.expectRevert();
        roleManager.newVault(
            address(asset),
            category,
            name,
            symbol,
            depositLimit
        );

        vm.prank(daddy);
        roleManager.newVault(
            address(asset),
            category + 1,
            name,
            "sdfsdf",
            depositLimit
        );
    }

    function test_add_new_vault__endorsed() public {
        uint256 category = 1;
        string memory name = " ksjdfl";
        string memory symbol = "sdfa";

        vm.prank(daddy);
        registry.setEndorser(address(roleManager), true);

        vm.prank(daddy);
        accountant.setVaultManager(address(roleManager));

        vm.prank(daddy);
        address newVaultAddress = registry.newEndorsedVault(
            address(asset),
            name,
            symbol,
            daddy,
            100
        );
        IVault newVault = IVault(newVaultAddress);

        vm.prank(user);
        vm.expectRevert("!allowed");
        roleManager.addNewVault(address(newVault), category);

        vm.expectRevert();
        roleManager.addNewVault(address(newVault), category);

        vm.prank(daddy);
        newVault.transfer_role_manager(address(roleManager));

        vm.prank(daddy);
        roleManager.addNewVault(address(newVault), category);

        (
            address vaultAsset,
            uint256 vaultCategory,
            address vaultDebtAllocator,
            uint256 index
        ) = roleManager.vaultConfig(address(newVault));

        assertEq(vaultAsset, address(asset));
        assertEq(vaultCategory, category);
        assertNotEq(vaultDebtAllocator, address(0));
        assertEq(index, 0);
        assertEq(roleManager.getAllVaults()[0], address(newVault));
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(newVault)
        );
        assertEq(roleManager.vaults(index), address(newVault));
        assertTrue(roleManager.isVaultsRoleManager(address(newVault)));
        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            vaultDebtAllocator
        );
        assertEq(roleManager.getCategory(address(newVault)), category);

        assertEq(newVault.roles(address(roleManager)), 0);
        assertEq(newVault.roles(daddy), daddy_roles);
    }

    function test_add_new_vault__not_endorsed() public {
        uint256 category = 1;
        string memory name = " ksjdfl";
        string memory symbol = "sdfa";

        vm.prank(daddy);
        registry.setEndorser(address(roleManager), true);

        vm.prank(daddy);
        accountant.setVaultManager(address(roleManager));

        vm.prank(daddy);
        address newVaultAddress = vaultFactory.deploy_new_vault(
            address(asset),
            name,
            symbol,
            daddy,
            100
        );
        IVault newVault = IVault(newVaultAddress);

        vm.prank(user);
        vm.expectRevert("!allowed");
        roleManager.addNewVault(address(newVault), category);

        vm.expectRevert();
        roleManager.addNewVault(address(newVault), category);

        vm.prank(daddy);
        newVault.transfer_role_manager(address(roleManager));

        vm.prank(daddy);
        roleManager.addNewVault(address(newVault), category);

        (
            address vaultAsset,
            uint256 vaultCategory,
            address vaultDebtAllocator,
            uint256 index
        ) = roleManager.vaultConfig(address(newVault));

        assertEq(vaultAsset, address(asset));
        assertEq(vaultCategory, category);
        assertNotEq(vaultDebtAllocator, address(0));
        assertEq(index, 0);
        assertEq(roleManager.getAllVaults()[0], address(newVault));
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(newVault)
        );
        assertEq(roleManager.vaults(index), address(newVault));
        assertTrue(roleManager.isVaultsRoleManager(address(newVault)));
        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            vaultDebtAllocator
        );
        assertEq(roleManager.getCategory(address(newVault)), category);
        assertEq(registry.numAssets(), 1);
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(registry.getAllEndorsedVaults()[0][0], address(newVault));

        assertEq(newVault.roles(address(roleManager)), 0);
    }

    function test_add_new_vault__with_debt_allocator() public {
        //setupRoleManager();

        string memory name = " ksjdfl";
        string memory symbol = "sdfa";
        uint256 category = 1;

        vm.prank(daddy);
        address newVaultAddress = vaultFactory.deploy_new_vault(
            address(asset),
            name,
            symbol,
            daddy,
            100
        );
        IVault newVault = IVault(newVaultAddress);

        assertEq(roleManager.getAllVaults().length, 0);
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(0)
        );
        assertEq(registry.numAssets(), 0);
        assertEq(registry.numEndorsedVaults(address(asset)), 0);

        vm.prank(brain);
        address debtAllocatorAddress = debtAllocatorFactory.newDebtAllocator(
            address(newVault)
        );
        DebtAllocator debtAllocator = DebtAllocator(debtAllocatorAddress);

        vm.prank(user);
        vm.expectRevert("!allowed");
        roleManager.addNewVault(
            address(newVault),
            category,
            address(debtAllocator)
        );

        vm.expectRevert();
        roleManager.addNewVault(
            address(newVault),
            category,
            address(debtAllocator)
        );

        vm.prank(daddy);
        newVault.transfer_role_manager(address(roleManager));

        vm.prank(daddy);
        roleManager.addNewVault(
            address(newVault),
            category,
            address(debtAllocator)
        );

        (
            address vaultAsset,
            uint256 vaultCategory,
            address vaultDebtAllocator,
            uint256 index
        ) = roleManager.vaultConfig(address(newVault));

        assertEq(vaultAsset, address(asset));
        assertEq(vaultCategory, category);
        assertEq(vaultDebtAllocator, address(debtAllocator));
        assertEq(index, 0);
        assertEq(roleManager.getAllVaults()[0], address(newVault));
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(newVault)
        );
        assertEq(roleManager.vaults(index), address(newVault));
        assertTrue(roleManager.isVaultsRoleManager(address(newVault)));
        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            address(debtAllocator)
        );
        assertEq(roleManager.getCategory(address(newVault)), category);
        assertEq(registry.numAssets(), 1);
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(registry.getAllEndorsedVaults()[0][0], address(newVault));

        assertEq(newVault.roles(address(roleManager)), 0);
        assertEq(newVault.roles(daddy), daddy_roles);
        assertEq(newVault.roles(brain), brain_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(newVault.roles(address(debtAllocator)), debt_allocator_roles);
        assertEq(newVault.profitMaxUnlockTime(), 100);

        assertEq(address(newVault.accountant()), address(accountant));
        assertTrue(accountant.vaults(address(newVault)));

        assertEq(newVault.maxDeposit(user), 0);

        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.name(), name);
    }

    function test_add_new_vault__with_accountant() public {
        //setupRoleManager();

        string memory name = " ksjdfl";
        string memory symbol = "sdfa";
        uint256 category = 1;

        vm.prank(daddy);
        address newVaultAddress = vaultFactory.deploy_new_vault(
            address(asset),
            name,
            symbol,
            daddy,
            100
        );
        IVault newVault = IVault(newVaultAddress);

        assertEq(roleManager.getAllVaults().length, 0);
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(0)
        );
        assertEq(registry.numAssets(), 0);
        assertEq(registry.numEndorsedVaults(address(asset)), 0);

        vm.prank(daddy);
        newVault.set_role(daddy, Roles.ALL);

        vm.prank(daddy);
        newVault.set_accountant(user);

        vm.prank(daddy);
        newVault.transfer_role_manager(address(roleManager));

        vm.prank(daddy);
        roleManager.addNewVault(address(newVault), category);

        (
            address vaultAsset,
            uint256 vaultCategory,
            address vaultDebtAllocator,
            uint256 index
        ) = roleManager.vaultConfig(address(newVault));

        assertEq(vaultAsset, address(asset));
        assertEq(vaultCategory, category);
        assertEq(vaultDebtAllocator, address(debtAllocator));
        assertEq(index, 0);
        assertEq(roleManager.getAllVaults()[0], address(newVault));
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(newVault)
        );
        assertEq(roleManager.vaults(index), address(newVault));
        assertTrue(roleManager.isVaultsRoleManager(address(newVault)));
        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            address(debtAllocator)
        );
        assertEq(roleManager.getCategory(address(newVault)), category);
        assertEq(registry.numAssets(), 1);
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(registry.getAllEndorsedVaults()[0][0], address(newVault));

        assertEq(newVault.roles(address(roleManager)), 0);
        assertEq(newVault.roles(daddy), daddy_roles);
        assertEq(newVault.roles(brain), brain_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(newVault.roles(address(debtAllocator)), debt_allocator_roles);
        assertEq(newVault.profitMaxUnlockTime(), 100);

        assertEq(address(newVault.accountant()), user);
        assertFalse(accountant.vaults(address(newVault)));

        assertEq(newVault.maxDeposit(user), 0);

        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.name(), name);
    }

    function test_add_new_vault__duplicate_reverts() public {
        string memory name = " ksjdfl";
        string memory symbol = "sdfa";
        uint256 category = 1;

        vm.prank(daddy);
        address newVaultAddress = vaultFactory.deploy_new_vault(
            address(asset),
            name,
            symbol,
            daddy,
            100
        );
        IVault newVault = IVault(newVaultAddress);

        vm.prank(brain);
        address debtAllocatorAddress = debtAllocatorFactory.newDebtAllocator(
            address(newVault)
        );
        DebtAllocator debtAllocator = DebtAllocator(debtAllocatorAddress);

        vm.prank(daddy);
        newVault.transfer_role_manager(address(roleManager));

        vm.prank(daddy);
        roleManager.addNewVault(
            address(newVault),
            category,
            address(debtAllocator)
        );

        vm.prank(daddy);
        vm.expectRevert();
        roleManager.addNewVault(
            address(newVault),
            category,
            address(debtAllocator)
        );
    }

    function test_new_debt_allocator__usesDefault() public {
        uint256 category = 1;
        string memory name = "sdfads";
        string memory symbol = "dsf";

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category,
            name,
            symbol
        );
        IVault newVault = IVault(newVaultAddress);

        (, , address vaultDebtAllocator, ) = roleManager.vaultConfig(
            address(newVault)
        );

        vm.prank(user);
        vm.expectRevert("!allowed");
        roleManager.updateDebtAllocator(address(newVault));

        vm.prank(brain);
        roleManager.updateDebtAllocator(address(newVault));

        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            vaultDebtAllocator
        );
        assertEq(newVault.roles(vaultDebtAllocator), debt_allocator_roles);
    }

    function test_new_debt_allocator__already_deployed() public {
        uint256 category = 1;
        string memory name = "sdfads";
        string memory symbol = "dsf";

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category,
            name,
            symbol
        );
        IVault newVault = IVault(newVaultAddress);

        (, , address vaultDebtAllocator, ) = roleManager.vaultConfig(
            address(newVault)
        );

        address newDebtAllocator = user;

        vm.prank(brain);
        roleManager.updateDebtAllocator(address(newVault), user);

        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            newDebtAllocator
        );
        assertEq(newVault.roles(vaultDebtAllocator), 0);
        assertEq(newVault.roles(user), debt_allocator_roles);
    }

    function test_updateKeeper() public {
        string memory name = "sdfads";
        string memory symbol = "dsf";

        address newKeeper = address(0x123);

        vm.prank(daddy);
        vault = IVault(roleManager.newVault(address(asset), 1, name, symbol));

        assertEq(roleManager.getKeeper(), address(keeper));
        assertEq(vault.roles(newKeeper), 0);
        assertEq(vault.roles(address(keeper)), keeper_roles);

        vm.expectRevert("!allowed");
        vm.prank(daddy);
        roleManager.updateKeeper(address(vault), newKeeper);

        vm.prank(brain);
        roleManager.updateKeeper(address(vault), newKeeper);

        assertEq(roleManager.getKeeper(), address(keeper));
        assertEq(vault.roles(newKeeper), keeper_roles);
        assertEq(vault.roles(address(keeper)), 0);
    }

    function test_remove_vault() public {
        uint256 category = 1;
        string memory name = "sdfads";
        string memory symbol = "dsf";

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category,
            name,
            symbol
        );
        IVault newVault = IVault(newVaultAddress);

        (
            address vaultAsset,
            uint256 vaultCategory,
            address vaultDebtAllocator,
            uint256 index
        ) = roleManager.vaultConfig(address(newVault));

        assertEq(vaultAsset, address(asset));
        assertEq(vaultCategory, category);
        assertNotEq(vaultDebtAllocator, address(0));
        assertEq(index, 0);
        assertEq(roleManager.getAllVaults()[0], address(newVault));
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(newVault)
        );
        assertEq(roleManager.vaults(index), address(newVault));
        assertTrue(roleManager.isVaultsRoleManager(address(newVault)));
        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            vaultDebtAllocator
        );
        assertEq(roleManager.getCategory(address(newVault)), category);

        DebtAllocator debtAllocator = DebtAllocator(vaultDebtAllocator);
        //(address(debtAllocator.vault()), address(newVault));

        vm.prank(user);
        vm.expectRevert("!allowed");
        roleManager.removeVault(address(newVault));

        vm.prank(brain);
        vm.expectRevert("vault not added");
        roleManager.removeVault(user);

        vm.prank(brain);
        vm.expectEmit(true, true, true, true);
        emit RemovedVault(address(newVault));
        roleManager.removeVault(address(newVault));

        assertEq(roleManager.getAllVaults().length, 0);
        assertEq(
            roleManager.getVault(
                address(asset),
                newVault.apiVersion(),
                category
            ),
            address(0)
        );
        assertFalse(roleManager.isVaultsRoleManager(address(newVault)));
        assertEq(roleManager.getDebtAllocator(address(newVault)), address(0));
        assertEq(roleManager.getCategory(address(newVault)), 0);

        // Still endorsed through the registry
        assertEq(registry.numAssets(), 1);
        assertEq(registry.numEndorsedVaults(address(asset)), 1);
        assertEq(registry.getAllEndorsedVaults()[0][0], address(newVault));

        // Check roles didn't change
        assertEq(newVault.roles(address(roleManager)), 0);
        assertEq(newVault.roles(daddy), daddy_roles);
        assertEq(newVault.roles(brain), brain_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(newVault.roles(vaultDebtAllocator), debt_allocator_roles);
        assertEq(
            newVault.profitMaxUnlockTime(),
            roleManager.defaultProfitMaxUnlockTime()
        );
        assertEq(newVault.future_role_manager(), daddy);
        assertEq(newVault.role_manager(), address(roleManager));

        vm.prank(daddy);
        newVault.accept_role_manager();

        assertEq(newVault.role_manager(), daddy);
    }
}
