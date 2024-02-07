import ape
from ape import project
from utils.constants import ZERO_ADDRESS, ROLES, MAX_INT
import pytest
from utils.helpers import to_bytes32

daddy_roles = ROLES.ALL
brain_roles = ROLES.REPORTING_MANAGER | ROLES.DEBT_MANAGER | ROLES.QUEUE_MANAGER
security_roles = ROLES.MAX_DEBT_MANAGER
keeper_roles = ROLES.REPORTING_MANAGER | ROLES.DEBT_MANAGER
debt_allocator_roles = ROLES.REPORTING_MANAGER | ROLES.DEBT_MANAGER
strategy_manager_roles = ROLES.ADD_STRATEGY_MANAGER | ROLES.REVOKE_STRATEGY_MANAGER


def test_role_manager_setup(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    healthcheck_accountant,
    registry,
    debt_allocator_factory,
    release_registry,
    vault,
    asset,
):
    assert role_manager.governance() == daddy
    assert role_manager.ratingToString(0) == ""
    assert role_manager.ratingToString(1) == "A"
    assert role_manager.ratingToString(2) == "B"
    assert role_manager.ratingToString(3) == "C"
    assert role_manager.ratingToString(4) == "D"
    assert role_manager.ratingToString(5) == "F"
    assert role_manager.ratingToString(6) == ""
    assert role_manager.chad() == daddy
    assert role_manager.getAllVaults() == []
    assert role_manager.getVault(asset, vault.apiVersion(), 1) == ZERO_ADDRESS
    assert role_manager.getDaddy() == daddy
    assert role_manager.getBrain() == brain
    assert role_manager.getSecurity() == security
    assert role_manager.getKeeper() == keeper
    assert role_manager.getStrategyManager() == strategy_manager
    assert role_manager.getRegistry() == registry
    assert role_manager.getAccountant() == healthcheck_accountant
    assert role_manager.getAllocatorFactory() == debt_allocator_factory
    assert role_manager.isVaultsRoleManager(vault) == False
    assert role_manager.getDebtAllocator(vault) == ZERO_ADDRESS
    assert role_manager.getRating(vault) == 0

    # Check registry too.
    assert registry.releaseRegistry() == release_registry
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0


def test__positions(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    healthcheck_accountant,
    registry,
    debt_allocator_factory,
    user,
):
    assert role_manager.getDaddy() == daddy
    assert role_manager.getBrain() == brain
    assert role_manager.getSecurity() == security
    assert role_manager.getKeeper() == keeper
    assert role_manager.getStrategyManager() == strategy_manager
    assert role_manager.getRegistry() == registry
    assert role_manager.getAccountant() == healthcheck_accountant
    assert role_manager.getAllocatorFactory() == debt_allocator_factory
    assert role_manager.getPositionHolder(role_manager.DADDY()) == daddy
    assert role_manager.getPositionHolder(role_manager.BRAIN()) == brain
    assert role_manager.getPositionHolder(role_manager.SECURITY()) == security
    assert role_manager.getPositionHolder(role_manager.KEEPER()) == keeper
    assert (
        role_manager.getPositionHolder(role_manager.STRATEGY_MANAGER())
        == strategy_manager
    )
    assert role_manager.getPositionHolder(role_manager.REGISTRY()) == registry
    assert (
        role_manager.getPositionHolder(role_manager.ACCOUNTANT())
        == healthcheck_accountant
    )
    assert (
        role_manager.getPositionHolder(role_manager.ALLOCATOR_FACTORY())
        == debt_allocator_factory
    )
    # Check roles
    assert role_manager.getDaddyRoles() == daddy_roles
    assert role_manager.getBrainRoles() == brain_roles
    assert role_manager.getSecurityRoles() == security_roles
    assert role_manager.getKeeperRoles() == keeper_roles
    assert role_manager.getDebtAllocatorRoles() == debt_allocator_roles
    assert role_manager.getStrategyManagerRoles() == strategy_manager_roles
    assert role_manager.getPositionRoles(role_manager.DADDY()) == daddy_roles
    assert role_manager.getPositionRoles(role_manager.BRAIN()) == brain_roles
    assert role_manager.getPositionRoles(role_manager.SECURITY()) == security_roles
    assert role_manager.getPositionRoles(role_manager.KEEPER()) == keeper_roles
    assert (
        role_manager.getPositionRoles(role_manager.DEBT_ALLOCATOR())
        == debt_allocator_roles
    )
    assert (
        role_manager.getPositionRoles(role_manager.STRATEGY_MANAGER())
        == strategy_manager_roles
    )

    id = to_bytes32("rando")
    assert role_manager.getPosition(id) == (ZERO_ADDRESS, 0)
    assert role_manager.getPositionHolder(id) == ZERO_ADDRESS
    assert role_manager.getPositionRoles(id) == 0

    with ape.reverts("!governance"):
        role_manager.setPositionHolder(id, user, sender=user)

    positions = {
        "Daddy": (daddy, daddy_roles),
        "Brain": (brain, brain_roles),
        "Security": (security, security_roles),
        "Keeper": (keeper, keeper_roles),
        "Strategy Manager": (strategy_manager, strategy_manager_roles),
        "Registry": (registry, 0),
        "Accountant": (healthcheck_accountant, 0),
        "Allocator Factory": (debt_allocator_factory, 0),
    }

    new_role = int(420_69)
    # Test each default role
    for name, position in positions.items():
        id = to_bytes32(name)
        assert role_manager.getPosition(id) == position
        assert role_manager.getPositionHolder(id) == position[0]
        assert role_manager.getPositionRoles(id) == position[1]

        tx = role_manager.setPositionHolder(id, user, sender=daddy)

        event = list(tx.decode_logs(role_manager.UpdatePositionHolder))[0]

        assert event.position == id
        assert event.newAddress == user

        assert role_manager.getPositionHolder(id) == user

        tx = role_manager.setPositionRoles(id, new_role, sender=daddy)

        event = list(tx.decode_logs(role_manager.UpdatePositionRoles))[0]

        assert event.position == id
        assert event.newRoles == new_role

        assert role_manager.getPositionRoles(id) == new_role
        assert role_manager.getPosition(id) == (user, new_role)

    # Cannot update the debt allocator roles.
    id = to_bytes32("Debt Allocator")
    with ape.reverts("cannot update"):
        role_manager.setPositionRoles(id, 1, sender=daddy)

    # But can update the holder since it is not used
    tx = role_manager.setPositionHolder(id, user, sender=daddy)

    event = list(tx.decode_logs(role_manager.UpdatePositionHolder))[0]

    assert event.position == id
    assert event.newAddress == user

    # All positions should be changed now.
    assert role_manager.getDaddy() == user
    assert role_manager.getBrain() == user
    assert role_manager.getSecurity() == user
    assert role_manager.getKeeper() == user
    assert role_manager.getStrategyManager() == user
    assert role_manager.getRegistry() == user
    assert role_manager.getAccountant() == user
    assert role_manager.getAllocatorFactory() == user
    assert role_manager.getPositionHolder(role_manager.DADDY()) == user
    assert role_manager.getPositionHolder(role_manager.BRAIN()) == user
    assert role_manager.getPositionHolder(role_manager.SECURITY()) == user
    assert role_manager.getPositionHolder(role_manager.KEEPER()) == user
    assert role_manager.getPositionHolder(role_manager.STRATEGY_MANAGER()) == user
    assert role_manager.getPositionHolder(role_manager.REGISTRY()) == user
    assert role_manager.getPositionHolder(role_manager.ACCOUNTANT()) == user
    assert role_manager.getPositionHolder(role_manager.ALLOCATOR_FACTORY()) == user
    # Check roles
    assert role_manager.getDaddyRoles() == new_role
    assert role_manager.getBrainRoles() == new_role
    assert role_manager.getSecurityRoles() == new_role
    assert role_manager.getKeeperRoles() == new_role
    assert role_manager.getDebtAllocatorRoles() == debt_allocator_roles
    assert role_manager.getStrategyManagerRoles() == new_role
    assert role_manager.getPositionRoles(role_manager.DADDY()) == new_role
    assert role_manager.getPositionRoles(role_manager.BRAIN()) == new_role
    assert role_manager.getPositionRoles(role_manager.SECURITY()) == new_role
    assert role_manager.getPositionRoles(role_manager.KEEPER()) == new_role
    assert (
        role_manager.getPositionRoles(role_manager.DEBT_ALLOCATOR())
        == debt_allocator_roles
    )
    assert role_manager.getPositionRoles(role_manager.STRATEGY_MANAGER()) == new_role


def test_setters(role_manager, daddy, user):
    assert role_manager.defaultProfitMaxUnlock() == 10 * 24 * 60 * 60  # 10 days

    # New default unlock time
    new_default_unlock_time = int(69)

    with ape.reverts("!governance"):
        role_manager.setDefaultProfitMaxUnlock(new_default_unlock_time, sender=user)

    tx = role_manager.setDefaultProfitMaxUnlock(new_default_unlock_time, sender=daddy)

    event = list(tx.decode_logs(role_manager.UpdateDefaultProfitMaxUnlock))[0]

    assert event.newDefaultProfitMaxUnlock == new_default_unlock_time
    assert role_manager.defaultProfitMaxUnlock() == new_default_unlock_time


def test_setters_with_zeros(
    role_manager,
    daddy,
    asset,
    release_registry,
    registry,
    vault_factory,
    healthcheck_accountant,
):
    id = to_bytes32("Security")

    role_manager.setPositionHolder(id, ZERO_ADDRESS, sender=daddy)
    role_manager.setPositionRoles(id, 0, sender=daddy)

    assert role_manager.getSecurity() == ZERO_ADDRESS
    assert role_manager.getSecurityRoles() == 0

    # Deploy a new vault
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    # Deploy a vault and doesnt revert
    tx = role_manager.newVault(asset, int(1), sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    assert vault != ZERO_ADDRESS


def test_deploy_new_vault(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    rating = int(1)
    deposit_limit = int(100e18)
    profit_unlock = int(695)

    release_registry.newRelease(vault_factory.address, sender=daddy)
    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    with ape.reverts("rating out of range"):
        role_manager.newVault(asset, 0, deposit_limit, profit_unlock, sender=daddy)

    with ape.reverts("rating out of range"):
        role_manager.newVault(asset, int(6), deposit_limit, profit_unlock, sender=daddy)

    with ape.reverts("!allowed"):
        role_manager.newVault(asset, rating, deposit_limit, profit_unlock, sender=user)

    # Now the registry will revert
    with ape.reverts("!endorser"):
        role_manager.newVault(asset, rating, deposit_limit, profit_unlock, sender=daddy)

    # ADd the role manager as an endorser
    registry.setEndorser(role_manager, True, sender=daddy)
    assert registry.endorsers(role_manager)

    # Haven't set the role manager as the vault manager.
    with ape.reverts("!vault manager"):
        role_manager.newVault(asset, rating, deposit_limit, profit_unlock, sender=daddy)

    healthcheck_accountant.setVaultManager(role_manager, sender=daddy)

    tx = role_manager.newVault(
        asset, rating, deposit_limit, profit_unlock, sender=daddy
    )

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]

    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    event = list(tx.decode_logs(role_manager.AddedNewVault))[0]

    assert event.vault == vault
    assert event.rating == rating
    allocator = event.debtAllocator

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]

    assert event.vault == vault
    debt_allocator = project.DebtAllocator.at(event.allocator)
    assert allocator == debt_allocator

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == profit_unlock

    # Check accountant
    assert vault.accountant() == healthcheck_accountant
    assert healthcheck_accountant.vaults(vault) == True

    # Check deposit limit
    assert vault.maxDeposit(user) == deposit_limit

    symbol = asset.symbol()
    assert vault.symbol() == f"yv{symbol}-A"
    assert vault.name() == f"{symbol} yVault-A"

    # Check debt allocator
    assert debt_allocator.vault() == vault


def test_deploy_new_vault__duplicate_reverts(
    role_manager,
    daddy,
    asset,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    rating = int(1)
    deposit_limit = int(100e18)
    profit_unlock = int(695)

    release_registry.newRelease(vault_factory.address, sender=daddy)
    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    # ADd the role manager as an endorser
    registry.setEndorser(role_manager, True, sender=daddy)
    assert registry.endorsers(role_manager)

    healthcheck_accountant.setVaultManager(role_manager, sender=daddy)

    tx = role_manager.newVault(
        asset, rating, deposit_limit, profit_unlock, sender=daddy
    )

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]

    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]

    assert event.vault == vault
    debt_allocator = project.DebtAllocator.at(event.allocator)

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Try and deploy a new one of the same settings.
    with ape.reverts(to_bytes32(f"Already Deployed {vault.address}")):
        role_manager.newVault(asset, rating, deposit_limit, profit_unlock, sender=daddy)

    # can with a different rating.
    role_manager.newVault(
        asset, rating + 1, deposit_limit, profit_unlock, max_fee="1", sender=daddy
    )


def test_deploy_new_vault__default_values(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    rating = int(2)

    release_registry.newRelease(vault_factory.address, sender=daddy)
    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    with ape.reverts("rating out of range"):
        role_manager.newVault(asset, 0, sender=daddy)

    with ape.reverts("rating out of range"):
        role_manager.newVault(asset, int(6), sender=daddy)

    with ape.reverts("!allowed"):
        role_manager.newVault(asset, rating, sender=user)

    # Now the registry will revert
    with ape.reverts("!endorser"):
        role_manager.newVault(asset, rating, sender=daddy)

    # ADd the role manager as an endorser
    registry.setEndorser(role_manager, True, sender=daddy)
    assert registry.endorsers(role_manager)

    # Haven't set the role manager as the vault manager.
    with ape.reverts("!vault manager"):
        role_manager.newVault(asset, rating, sender=daddy)

    healthcheck_accountant.setVaultManager(role_manager, sender=daddy)

    # User can now deploy
    tx = role_manager.newVault(asset, rating, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]

    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    event = list(tx.decode_logs(role_manager.AddedNewVault))[0]

    assert event.vault == vault
    assert event.rating == rating

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]

    assert event.vault == vault
    debt_allocator = project.DebtAllocator.at(event.allocator)

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == role_manager.defaultProfitMaxUnlock()

    # Check accountant
    assert vault.accountant() == healthcheck_accountant
    assert healthcheck_accountant.vaults(vault) == True

    # Check deposit limit
    assert vault.maxDeposit(user) == 0

    symbol = asset.symbol()
    assert vault.symbol() == f"yv{symbol}-B"
    assert vault.name() == f"{symbol} yVault-B"

    # Check debt allocator
    assert debt_allocator.vault() == vault


def setup_role_manager(
    role_manager, release_registry, registry, vault_factory, accountant, daddy
):
    release_registry.newRelease(vault_factory.address, sender=daddy)
    # ADd the role manager as an endorser
    registry.setEndorser(role_manager, True, sender=daddy)
    assert registry.endorsers(role_manager)
    accountant.setVaultManager(role_manager, sender=daddy)


def test_add_new_vault__endorsed(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    name = " ksjdfl"
    symbol = "sdfa"
    rating = int(1)

    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    tx = registry.newEndorsedVault(asset, name, symbol, daddy, 100, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    with ape.reverts("!allowed"):
        role_manager.addNewVault(vault, rating, sender=user)

    with ape.reverts("rating out of range"):
        role_manager.addNewVault(vault, 0, sender=daddy)

    with ape.reverts("rating out of range"):
        role_manager.addNewVault(vault, 6, sender=daddy)

    # Is not pending role manager
    with ape.reverts():
        role_manager.addNewVault(vault, rating, sender=user)

    vault.transfer_role_manager(role_manager, sender=daddy)

    tx = role_manager.addNewVault(vault, rating, sender=daddy)

    event = list(tx.decode_logs(role_manager.AddedNewVault))[0]

    assert event.vault == vault
    assert event.rating == rating

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]

    assert event.vault == vault
    debt_allocator = project.DebtAllocator.at(event.allocator)

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == 100

    # Check accountant
    assert vault.accountant() == healthcheck_accountant
    assert healthcheck_accountant.vaults(vault) == True

    # Check deposit limit
    assert vault.maxDeposit(user) == 0

    assert vault.symbol() == symbol
    assert vault.name() == name

    # Check debt allocator
    assert debt_allocator.vault() == vault


def test_add_new_vault__not_endorsed(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    name = " ksjdfl"
    symbol = "sdfa"
    rating = int(1)

    tx = vault_factory.deploy_new_vault(asset, name, symbol, daddy, 100, sender=daddy)

    event = list(tx.decode_logs(vault_factory.NewVault))[0]
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event.vault_address
    )

    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    with ape.reverts("!allowed"):
        role_manager.addNewVault(vault, rating, sender=user)

    with ape.reverts("rating out of range"):
        role_manager.addNewVault(vault, 0, sender=daddy)

    with ape.reverts("rating out of range"):
        role_manager.addNewVault(vault, 6, sender=daddy)

    # Is not pending role manager
    with ape.reverts():
        role_manager.addNewVault(vault, rating, sender=user)

    vault.transfer_role_manager(role_manager, sender=daddy)

    tx = role_manager.addNewVault(vault, rating, sender=daddy)

    event = list(tx.decode_logs(role_manager.AddedNewVault))[0]

    assert event.vault == vault
    assert event.rating == rating

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]

    assert event.vault == vault
    debt_allocator = project.DebtAllocator.at(event.allocator)

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == 100

    # Check accountant
    assert vault.accountant() == healthcheck_accountant
    assert healthcheck_accountant.vaults(vault) == True

    # Check deposit limit
    assert vault.maxDeposit(user) == 0

    assert vault.symbol() == symbol
    assert vault.name() == name

    # Check debt allocator
    assert debt_allocator.vault() == vault


def test_add_new_vault__with_debt_allocator(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    name = " ksjdfl"
    symbol = "sdfa"
    rating = int(1)

    tx = vault_factory.deploy_new_vault(asset, name, symbol, daddy, 100, sender=daddy)

    event = list(tx.decode_logs(vault_factory.NewVault))[0]
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event.vault_address
    )

    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    tx = debt_allocator_factory.newDebtAllocator(vault, sender=brain)
    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]
    assert event.vault == vault
    debt_allocator = project.DebtAllocator.at(event.allocator)

    with ape.reverts("!allowed"):
        role_manager.addNewVault(vault, rating, debt_allocator, sender=user)

    with ape.reverts("rating out of range"):
        role_manager.addNewVault(vault, 0, debt_allocator, sender=daddy)

    with ape.reverts("rating out of range"):
        role_manager.addNewVault(vault, 6, debt_allocator, sender=daddy)

    # Is not pending role manager
    with ape.reverts():
        role_manager.addNewVault(vault, rating, debt_allocator, sender=user)

    vault.transfer_role_manager(role_manager, sender=daddy)

    tx = role_manager.addNewVault(vault, rating, debt_allocator, sender=daddy)

    event = list(tx.decode_logs(role_manager.AddedNewVault))[0]

    assert event.vault == vault
    assert event.rating == rating
    assert event.debtAllocator == debt_allocator

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == 100

    # Check accountant
    assert vault.accountant() == healthcheck_accountant
    assert healthcheck_accountant.vaults(vault) == True

    # Check deposit limit
    assert vault.maxDeposit(user) == 0

    assert vault.symbol() == symbol
    assert vault.name() == name

    # Check debt allocator
    assert debt_allocator.vault() == vault


def test_add_new_vault__with_accountant(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    name = " ksjdfl"
    symbol = "sdfa"
    rating = int(1)
    tx = vault_factory.deploy_new_vault(asset, name, symbol, daddy, 100, sender=daddy)

    event = list(tx.decode_logs(vault_factory.NewVault))[0]
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event.vault_address
    )

    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    tx = debt_allocator_factory.newDebtAllocator(vault, sender=brain)
    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]
    assert event.vault == vault
    debt_allocator = project.DebtAllocator.at(event.allocator)

    vault.add_role(daddy, ROLES.ACCOUNTANT_MANAGER, sender=daddy)
    vault.set_accountant(user, sender=daddy)
    vault.remove_role(daddy, ROLES.ACCOUNTANT_MANAGER, sender=daddy)

    with ape.reverts("!allowed"):
        role_manager.addNewVault(vault, rating, debt_allocator, sender=user)

    with ape.reverts("rating out of range"):
        role_manager.addNewVault(vault, 0, debt_allocator, sender=daddy)

    with ape.reverts("rating out of range"):
        role_manager.addNewVault(vault, 6, debt_allocator, sender=daddy)

    # Is not pending role manager
    with ape.reverts():
        role_manager.addNewVault(vault, rating, debt_allocator, sender=user)

    vault.transfer_role_manager(role_manager, sender=daddy)

    tx = role_manager.addNewVault(vault, rating, debt_allocator, sender=daddy)

    event = list(tx.decode_logs(role_manager.AddedNewVault))[0]

    assert event.vault == vault
    assert event.rating == rating
    assert event.debtAllocator == debt_allocator

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == 100

    # Check accountant
    assert vault.accountant() == user
    assert healthcheck_accountant.vaults(vault) == False

    # Check deposit limit
    assert vault.maxDeposit(user) == 0

    assert vault.symbol() == symbol
    assert vault.name() == name

    # Check debt allocator
    assert debt_allocator.vault() == vault


def test_add_new_vault__duplicate_reverts(
    role_manager,
    daddy,
    asset,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    rating = int(1)
    deposit_limit = int(100e18)
    profit_unlock = int(695)

    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    tx = role_manager.newVault(
        asset, rating, deposit_limit, profit_unlock, sender=daddy
    )

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]

    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]

    assert event.vault == vault
    debt_allocator = project.DebtAllocator.at(event.allocator)

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating

    name = " ksjdfl"
    symbol = "sdfa"

    # Deploy a new vault with the same asset
    tx = vault_factory.deploy_new_vault(asset, name, symbol, daddy, 100, sender=daddy)

    event = list(tx.decode_logs(vault_factory.NewVault))[0]
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event.vault_address
    )

    with ape.reverts(to_bytes32(f"Already Deployed {vault.address}")):
        role_manager.addNewVault(new_vault, rating, debt_allocator, sender=daddy)

    # Can add it with a different rating.
    role_manager.addNewVault(vault, rating + 1, debt_allocator, sender=daddy)


def test_new_debt_allocator__deploys_one(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    rating = int(2)

    assert role_manager.getAllVaults() == []
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    # Deploy a vault
    tx = role_manager.newVault(asset, rating, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]
    debt_allocator = project.DebtAllocator.at(event.allocator)

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == role_manager.defaultProfitMaxUnlock()

    # Check debt allocator
    assert debt_allocator.vault() == vault

    # Update to a new debt allocator
    with ape.reverts("!allowed"):
        role_manager.updateDebtAllocator(vault, sender=user)

    with ape.reverts("vault not added"):
        role_manager.updateDebtAllocator(user, sender=brain)

    tx = role_manager.updateDebtAllocator(vault, sender=brain)

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]
    new_debt_allocator = project.DebtAllocator.at(event.allocator)

    event = list(tx.decode_logs(role_manager.UpdateDebtAllocator))[0]

    assert event.vault == vault
    assert event.debtAllocator == new_debt_allocator

    assert new_debt_allocator != debt_allocator
    assert new_debt_allocator.vault() == vault

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == new_debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == new_debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == 0
    assert vault.roles(new_debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == role_manager.defaultProfitMaxUnlock()


def test_new_debt_allocator__already_deployed(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    rating = int(2)

    assert role_manager.getAllVaults() == []
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    # Deploy a vault
    tx = role_manager.newVault(asset, rating, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]
    debt_allocator = project.DebtAllocator.at(event.allocator)

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == role_manager.defaultProfitMaxUnlock()

    # Check debt allocator
    assert debt_allocator.vault() == vault
    tx = debt_allocator_factory.newDebtAllocator(vault, sender=brain)
    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]
    new_debt_allocator = project.DebtAllocator.at(event.allocator)

    # Update to a new debt allocator
    with ape.reverts("!allowed"):
        role_manager.updateDebtAllocator(vault, new_debt_allocator, sender=user)

    with ape.reverts("vault not added"):
        role_manager.updateDebtAllocator(user, new_debt_allocator, sender=brain)

    tx = role_manager.updateDebtAllocator(vault, new_debt_allocator, sender=brain)

    event = list(tx.decode_logs(role_manager.UpdateDebtAllocator))[0]

    assert event.vault == vault
    assert event.debtAllocator == new_debt_allocator

    assert new_debt_allocator != debt_allocator
    assert new_debt_allocator.vault() == vault

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == new_debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == new_debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == 0
    assert vault.roles(new_debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == role_manager.defaultProfitMaxUnlock()


def test_remove_vault(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    rating = int(2)

    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    # Deploy a vault
    tx = role_manager.newVault(asset, rating, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]
    debt_allocator = project.DebtAllocator.at(event.allocator)

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True
    assert role_manager.getDebtAllocator(vault) == debt_allocator
    assert role_manager.getRating(vault) == rating
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == role_manager.defaultProfitMaxUnlock()

    # Check debt allocator
    assert debt_allocator.vault() == vault

    # Remove the vault
    with ape.reverts("!allowed"):
        role_manager.removeVault(vault, sender=user)

    with ape.reverts("vault not added"):
        role_manager.removeVault(user, sender=daddy)

    tx = role_manager.removeVault(vault, sender=daddy)

    event = list(tx.decode_logs(role_manager.RemovedVault))[0]
    assert event.vault == vault

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == ZERO_ADDRESS
    assert vault_rating == 0
    assert vault_debt_allocator == ZERO_ADDRESS
    assert index == 0
    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert role_manager.isVaultsRoleManager(vault) == False
    assert role_manager.getDebtAllocator(vault) == ZERO_ADDRESS
    assert role_manager.getRating(vault) == 0
    # Still endorsed through the registry
    assert registry.numAssets() == 1
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getAllEndorsedVaults() == [[vault]]

    # Check roles didnt chance
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles
    assert vault.roles(brain) == brain_roles
    assert vault.roles(security) == security_roles
    assert vault.roles(keeper) == keeper_roles
    assert vault.roles(debt_allocator) == debt_allocator_roles
    assert vault.roles(strategy_manager) == strategy_manager_roles
    assert vault.profitMaxUnlockTime() == role_manager.defaultProfitMaxUnlock()
    assert vault.future_role_manager() == daddy
    assert vault.role_manager() == role_manager

    vault.accept_role_manager(sender=daddy)

    assert vault.role_manager() == daddy


def test_remove_role(
    role_manager,
    daddy,
    brain,
    security,
    keeper,
    strategy_manager,
    asset,
    user,
    strategy,
    healthcheck_accountant,
    registry,
    release_registry,
    vault_factory,
    debt_allocator_factory,
):
    setup_role_manager(
        role_manager=role_manager,
        release_registry=release_registry,
        registry=registry,
        vault_factory=vault_factory,
        accountant=healthcheck_accountant,
        daddy=daddy,
    )

    rating = int(2)

    assert role_manager.getAllVaults() == []
    assert (
        role_manager.getVault(asset, vault_factory.apiVersion(), rating) == ZERO_ADDRESS
    )
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0

    # Deploy a vault
    tx = role_manager.newVault(asset, rating, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))[0]
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event.vault)

    event = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))[0]
    debt_allocator = project.DebtAllocator.at(event.allocator)

    (vault_asset, vault_rating, vault_debt_allocator, index) = role_manager.vaultConfig(
        vault
    )

    assert vault_asset == asset
    assert vault_rating == rating
    assert vault_debt_allocator == debt_allocator
    assert index == 0
    assert role_manager.getAllVaults() == [vault]
    assert role_manager.getVault(asset, vault_factory.apiVersion(), rating) == vault
    assert role_manager.vaults(index) == vault
    assert role_manager.isVaultsRoleManager(vault) == True

    # Check roles
    assert vault.roles(role_manager) == 0
    assert vault.roles(daddy) == daddy_roles

    # Remove 1 role and see if the rest remain the same.
    new_roles = daddy_roles & ~ROLES.ADD_STRATEGY_MANAGER

    with ape.reverts("vault not added"):
        role_manager.removeRoles(
            [strategy], daddy, ROLES.ADD_STRATEGY_MANAGER, sender=daddy
        )

    with ape.reverts("!governance"):
        role_manager.removeRoles(
            [vault], daddy, ROLES.ADD_STRATEGY_MANAGER, sender=user
        )

    tx = role_manager.removeRoles(
        [vault], daddy, ROLES.ADD_STRATEGY_MANAGER, sender=daddy
    )

    event = list(tx.decode_logs(vault.RoleSet))

    assert len(event) == 1
    assert event[0].account == daddy
    assert event[0].role == new_roles
    assert vault.roles(daddy) == new_roles

    with ape.reverts("not allowed"):
        vault.add_strategy(strategy, sender=daddy)

    # Remove two roles at once
    to_remove = ROLES.REVOKE_STRATEGY_MANAGER | ROLES.FORCE_REVOKE_MANAGER

    new_roles = new_roles & ~to_remove

    tx = role_manager.removeRoles([vault], daddy, to_remove, sender=daddy)

    event = list(tx.decode_logs(vault.RoleSet))

    assert len(event) == 1
    assert event[0].account == daddy
    assert event[0].role == new_roles
    assert vault.roles(daddy) == new_roles

    with ape.reverts("not allowed"):
        vault.revoke_strategy(strategy, sender=daddy)

    with ape.reverts("not allowed"):
        vault.force_revoke_strategy(strategy, sender=daddy)
