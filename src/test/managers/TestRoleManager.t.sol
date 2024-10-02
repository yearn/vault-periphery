// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, RoleManager, IVault, Roles, MockStrategy, DebtAllocator} from "../utils/Setup.sol";

contract TestRoleManager is Setup {
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
    uint256 constant security_roles = Roles.MAX_DEBT_MANAGER;
    uint256 constant keeper_roles = Roles.REPORTING_MANAGER;
    uint256 constant debt_allocator_roles =
        Roles.REPORTING_MANAGER | Roles.DEBT_MANAGER;
    uint256 constant strategy_manager_roles =
        Roles.ADD_STRATEGY_MANAGER | Roles.REVOKE_STRATEGY_MANAGER;

    function setUp() public override {
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
        assertEq(roleManager.governance(), daddy);
        assertEq(roleManager.chad(), daddy);
        assertEq(roleManager.getAllVaults().length, 0);
        assertEq(
            roleManager.getVault(address(asset), vault.apiVersion(), 1),
            address(0)
        );
        assertEq(roleManager.getDaddy(), daddy);
        assertEq(roleManager.getBrain(), brain);
        assertEq(roleManager.getSecurity(), security);
        assertEq(roleManager.getKeeper(), address(keeper));
        assertEq(roleManager.getStrategyManager(), strategyManager);
        assertEq(roleManager.getRegistry(), address(registry));
        assertEq(roleManager.getAccountant(), address(accountant));
        assertEq(
            roleManager.getAllocatorFactory(),
            address(debtAllocatorFactory)
        );
        assertFalse(roleManager.isVaultsRoleManager(address(vault)));
        assertEq(roleManager.getDebtAllocator(address(vault)), address(0));
        assertEq(roleManager.getCategory(address(vault)), 0);

        // Check registry too.
        assertEq(address(registry.releaseRegistry()), address(releaseRegistry));
        assertEq(registry.numAssets(), 0);
        assertEq(registry.numEndorsedVaults(address(asset)), 0);
    }

    function test__positions() public {
        assertEq(roleManager.getDaddy(), daddy);
        assertEq(roleManager.getBrain(), brain);
        assertEq(roleManager.getSecurity(), security);
        assertEq(roleManager.getKeeper(), address(keeper));
        assertEq(roleManager.getStrategyManager(), strategyManager);
        assertEq(roleManager.getRegistry(), address(registry));
        assertEq(roleManager.getAccountant(), address(accountant));
        assertEq(
            roleManager.getAllocatorFactory(),
            address(debtAllocatorFactory)
        );
        assertEq(roleManager.getPositionHolder(roleManager.DADDY()), daddy);
        assertEq(roleManager.getPositionHolder(roleManager.BRAIN()), brain);
        assertEq(
            roleManager.getPositionHolder(roleManager.SECURITY()),
            security
        );
        assertEq(
            roleManager.getPositionHolder(roleManager.KEEPER()),
            address(keeper)
        );
        assertEq(
            roleManager.getPositionHolder(roleManager.STRATEGY_MANAGER()),
            strategyManager
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
            roleManager.getPositionHolder(roleManager.ALLOCATOR_FACTORY()),
            address(debtAllocatorFactory)
        );

        // Check roles
        assertEq(roleManager.getDaddyRoles(), daddy_roles);
        assertEq(roleManager.getBrainRoles(), brain_roles);
        assertEq(roleManager.getSecurityRoles(), security_roles);
        assertEq(roleManager.getKeeperRoles(), keeper_roles);
        assertEq(roleManager.getDebtAllocatorRoles(), debt_allocator_roles);
        assertEq(roleManager.getStrategyManagerRoles(), strategy_manager_roles);
        assertEq(
            roleManager.getPositionRoles(roleManager.DADDY()),
            daddy_roles
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.BRAIN()),
            brain_roles
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.SECURITY()),
            security_roles
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.KEEPER()),
            keeper_roles
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.DEBT_ALLOCATOR()),
            debt_allocator_roles
        );
        assertEq(
            roleManager.getPositionRoles(roleManager.STRATEGY_MANAGER()),
            strategy_manager_roles
        );

        bytes32 id = keccak256("rando");
        (address holder, uint256 roles) = roleManager.getPosition(id);
        assertEq(holder, address(0));
        assertEq(roles, 0);
        assertEq(roleManager.getPositionHolder(id), address(0));
        assertEq(roleManager.getPositionRoles(id), 0);

        vm.prank(user);
        vm.expectRevert("!governance");
        roleManager.setPositionHolder(id, user);

        bytes32[7] memory positionIds = [
            roleManager.DADDY(),
            roleManager.BRAIN(),
            roleManager.SECURITY(),
            roleManager.STRATEGY_MANAGER(),
            roleManager.REGISTRY(),
            roleManager.ACCOUNTANT(),
            roleManager.ALLOCATOR_FACTORY()
        ];

        address[7] memory positionHolders = [
            daddy,
            brain,
            security,
            strategyManager,
            address(registry),
            address(accountant),
            address(debtAllocatorFactory)
        ];

        uint256[7] memory positionRoles = [
            daddy_roles,
            brain_roles,
            security_roles,
            strategy_manager_roles,
            0,
            0,
            0
        ];

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

        // All positions should be changed now.
        assertEq(roleManager.getDaddy(), user);
        assertEq(roleManager.getBrain(), user);
        assertEq(roleManager.getSecurity(), user);
        assertEq(roleManager.getKeeper(), user);
        assertEq(roleManager.getStrategyManager(), user);
        assertEq(roleManager.getRegistry(), user);
        assertEq(roleManager.getAccountant(), user);
        assertEq(roleManager.getAllocatorFactory(), user);
        assertEq(roleManager.getPositionHolder(roleManager.DADDY()), user);
        assertEq(roleManager.getPositionHolder(roleManager.BRAIN()), user);
        assertEq(roleManager.getPositionHolder(roleManager.SECURITY()), user);
        assertEq(roleManager.getPositionHolder(roleManager.KEEPER()), user);
        assertEq(
            roleManager.getPositionHolder(roleManager.STRATEGY_MANAGER()),
            user
        );
        assertEq(roleManager.getPositionHolder(roleManager.REGISTRY()), user);
        assertEq(roleManager.getPositionHolder(roleManager.ACCOUNTANT()), user);
        assertEq(
            roleManager.getPositionHolder(roleManager.ALLOCATOR_FACTORY()),
            user
        );

        // Check roles
        assertEq(roleManager.getDaddyRoles(), new_role);
        assertEq(roleManager.getBrainRoles(), new_role);
        assertEq(roleManager.getSecurityRoles(), new_role);
        assertEq(roleManager.getKeeperRoles(), keeper_roles);
        assertEq(roleManager.getDebtAllocatorRoles(), debt_allocator_roles);
        assertEq(roleManager.getStrategyManagerRoles(), new_role);
        assertEq(roleManager.getPositionRoles(roleManager.DADDY()), new_role);
        assertEq(roleManager.getPositionRoles(roleManager.BRAIN()), new_role);
        assertEq(
            roleManager.getPositionRoles(roleManager.SECURITY()),
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
        assertEq(
            roleManager.getPositionRoles(roleManager.STRATEGY_MANAGER()),
            new_role
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
        address newVault = roleManager.newVault(address(asset), 1);

        assertNeq(newVault, address(0));
    }

    function test_deploy_new_vault__default_values() public {
        uint256 category = 2;

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category
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
        assertEq(newVault.roles(security), security_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(
            newVault.roles(address(vault_debt_allocator)),
            debt_allocator_roles
        );
        assertEq(newVault.roles(strategyManager), strategy_manager_roles);
        assertEq(
            newVault.profitMaxUnlockTime(),
            roleManager.defaultProfitMaxUnlock()
        );

        // Check accountant
        assertEq(address(newVault.accountant()), address(accountant));
        assertTrue(accountant.vaults(address(newVault)));

        // Check deposit limit
        assertEq(newVault.maxDeposit(user), 0);

        string memory symbol = asset.symbol();
        assertEq(
            newVault.symbol(),
            string(abi.encodePacked("yv", symbol, "-2"))
        );
        assertEq(
            newVault.name(),
            string(abi.encodePacked(symbol, "-2 yVault"))
        );

        // Check debt allocator
        //assertEq(debtAllocator.vault(), address(newVault));
    }

    function test_remove_role() public {
        uint256 category = 2;

        address[] memory vaults = new address[](1);

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category
        );
        IVault newVault = IVault(newVaultAddress);

        uint256 new_roles = daddy_roles & ~Roles.ADD_STRATEGY_MANAGER;

        vaults[0] = address(strategy);

        vm.prank(daddy);
        vm.expectRevert("vault not added");
        roleManager.removeRoles(vaults, daddy, Roles.ADD_STRATEGY_MANAGER);

        vaults[0] = address(newVault);

        vm.prank(user);
        vm.expectRevert("!governance");
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

        vm.prank(daddy);
        roleManager.setPositionHolder(id, address(0));

        vm.prank(daddy);
        roleManager.setPositionRoles(id, 0);

        (address holder, uint256 roles) = roleManager.getPosition(id);
        assertEq(holder, address(0));
        assertEq(roles, 0);

        vm.prank(daddy);
        address newVault = roleManager.newVault(address(asset), 1);

        assertNotEq(newVault, address(0));
    }

    function test_deploy_new_vault() public {
        uint256 category = 1;
        uint256 depositLimit = 100e18;
        uint256 profitUnlock = 695;

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
            depositLimit,
            profitUnlock
        );

        vm.prank(daddy);
        vm.expectRevert("!endorser");
        roleManager.newVault(
            address(asset),
            category,
            depositLimit,
            profitUnlock
        );

        vm.prank(daddy);
        registry.setEndorser(address(roleManager), true);
        assertTrue(registry.endorsers(address(roleManager)));

        vm.prank(daddy);
        vm.expectRevert("!vault manager");
        roleManager.newVault(
            address(asset),
            category,
            depositLimit,
            profitUnlock
        );

        vm.prank(daddy);
        accountant.setVaultManager(address(roleManager));

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category,
            depositLimit,
            profitUnlock
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
        assertEq(newVault.roles(security), security_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(newVault.roles(vaultDebtAllocator), debt_allocator_roles);
        assertEq(newVault.roles(strategyManager), strategy_manager_roles);
        assertEq(newVault.profitMaxUnlockTime(), profitUnlock);

        assertEq(address(newVault.accountant()), address(accountant));
        assertTrue(accountant.vaults(address(newVault)));

        assertEq(newVault.maxDeposit(user), depositLimit);

        string memory symbol = asset.symbol();
        assertEq(
            newVault.symbol(),
            string(abi.encodePacked("yv", symbol, "-1"))
        );
        assertEq(
            newVault.name(),
            string(abi.encodePacked(symbol, "-1 yVault"))
        );
    }

    function test_deploy_new_vault__duplicate_reverts() public {
        uint256 category = 1;
        uint256 depositLimit = 100e18;
        uint256 profitUnlock = 695;

        vm.prank(daddy);
        registry.setEndorser(address(roleManager), true);

        vm.prank(daddy);
        accountant.setVaultManager(address(roleManager));

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category,
            depositLimit,
            profitUnlock
        );
        IVault newVault = IVault(newVaultAddress);

        vm.prank(daddy);
        bytes memory revertData = abi.encodePacked(
            "Already Deployed ",
            abi.encode(address(newVault))
        );
        vm.expectRevert(revertData);
        roleManager.newVault(
            address(asset),
            category,
            depositLimit,
            profitUnlock
        );

        vm.prank(daddy);
        roleManager.newVault(
            address(asset),
            category + 1,
            depositLimit,
            profitUnlock
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
        assertEq(newVault.roles(security), security_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(newVault.roles(address(debtAllocator)), debt_allocator_roles);
        assertEq(newVault.roles(strategyManager), strategy_manager_roles);
        assertEq(newVault.profitMaxUnlockTime(), 100);

        assertEq(address(newVault.accountant()), address(accountant));
        assertTrue(accountant.vaults(address(newVault)));

        assertEq(newVault.maxDeposit(user), 0);

        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.name(), name);

        //assertEq(address(debtAllocator.vault()), address(newVault));
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

        vm.prank(brain);
        address debtAllocatorAddress = debtAllocatorFactory.newDebtAllocator(
            address(newVault)
        );
        DebtAllocator debtAllocator = DebtAllocator(debtAllocatorAddress);

        vm.prank(daddy);
        newVault.set_accountant(user);

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
        assertEq(newVault.roles(security), security_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(newVault.roles(address(debtAllocator)), debt_allocator_roles);
        assertEq(newVault.roles(strategyManager), strategy_manager_roles);
        assertEq(newVault.profitMaxUnlockTime(), 100);

        assertEq(address(newVault.accountant()), user);
        assertFalse(accountant.vaults(address(newVault)));

        assertEq(newVault.maxDeposit(user), 0);

        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.name(), name);

        //assertEq(address(debtAllocator.vault()), address(newVault));
    }

    function test_add_new_vault__duplicate_reverts() public {
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
        vm.expectRevert("vault already added");
        roleManager.addNewVault(
            address(newVault),
            category,
            address(debtAllocator)
        );
    }

    function test_new_debt_allocator__deploys_one() public {
        //setupRoleManager();

        uint256 category = 1;

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category
        );
        IVault newVault = IVault(newVaultAddress);

        (, , address vaultDebtAllocator, ) = roleManager.vaultConfig(
            address(newVault)
        );

        vm.prank(user);
        vm.expectRevert("!allowed");
        roleManager.updateDebtAllocator(address(newVault));

        vm.prank(brain);
        vm.expectRevert("debt allocator already deployed");
        roleManager.updateDebtAllocator(address(newVault));

        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            vaultDebtAllocator
        );
    }

    function test_new_debt_allocator__already_deployed() public {
        //setupRoleManager();

        uint256 category = 1;

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category
        );
        IVault newVault = IVault(newVaultAddress);

        (, , address vaultDebtAllocator, ) = roleManager.vaultConfig(
            address(newVault)
        );

        vm.prank(brain);
        vm.expectRevert("debt allocator already deployed");
        roleManager.updateDebtAllocator(address(newVault));

        assertEq(
            roleManager.getDebtAllocator(address(newVault)),
            vaultDebtAllocator
        );
    }

    function test_new_keeper() public {
        //setupRoleManager();

        address newKeeper = address(0x123);
        bytes32 keeperId = roleManager.KEEPER();
        vm.prank(user);
        vm.expectRevert("!governance");
        roleManager.setPositionHolder(keeperId, newKeeper);

        vm.prank(daddy);
        vm.expectEmit(true, true, true, true);
        emit UpdatePositionHolder(roleManager.KEEPER(), newKeeper);
        roleManager.setPositionHolder(roleManager.KEEPER(), newKeeper);

        assertEq(roleManager.getKeeper(), newKeeper);
        assertEq(
            roleManager.getPositionHolder(roleManager.KEEPER()),
            newKeeper
        );

        uint256 category = 1;

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category
        );
        IVault newVault = IVault(newVaultAddress);

        assertEq(newVault.roles(newKeeper), keeper_roles);
    }

    function test_remove_vault() public {
        //setupRoleManager();

        uint256 category = 1;

        vm.prank(daddy);
        address newVaultAddress = roleManager.newVault(
            address(asset),
            category
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

        vm.prank(daddy);
        vm.expectRevert("vault not added");
        roleManager.removeVault(user);

        vm.prank(daddy);
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
        assertEq(newVault.roles(security), security_roles);
        assertEq(newVault.roles(address(keeper)), keeper_roles);
        assertEq(newVault.roles(vaultDebtAllocator), debt_allocator_roles);
        assertEq(newVault.roles(strategyManager), strategy_manager_roles);
        assertEq(
            newVault.profitMaxUnlockTime(),
            roleManager.defaultProfitMaxUnlock()
        );
        assertEq(newVault.future_role_manager(), daddy);
        assertEq(newVault.role_manager(), address(roleManager));

        vm.prank(daddy);
        newVault.accept_role_manager();

        assertEq(newVault.role_manager(), daddy);
    }
}
