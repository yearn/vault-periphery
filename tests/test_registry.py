import ape
from ape import project
from utils.constants import WEEK
import pytest


def add_new_release(release_registry, factory, owner):
    tx = release_registry.newRelease(factory.address, sender=owner)

    event = list(tx.decode_logs(release_registry.NewRelease))

    assert len(event) == 1
    assert event[0].factory == factory
    assert event[0].apiVersion == factory.api_version()


def test__set_up(registry, asset, release_registry, daddy):
    assert registry.governance() == daddy
    assert registry.releaseRegistry() == release_registry
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0
    assert registry.numEndorsedStrategies(asset) == 0


def test__deploy_new_vault(registry, asset, release_registry, vault_factory, daddy):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    name = "New vaults"
    symbol = "yvTest"

    # Deploy a new vault
    tx = registry.newEndorsedVault(asset, name, symbol, daddy, WEEK, 0, sender=daddy)

    address = tx.return_value
    new_vault = project.dependencies["yearn-vaults"]["master"].VaultV3.at(address)
    block = tx.timestamp

    event = list(tx.decode_logs(registry.NewEndorsedVault))
    # new_vault = project.dependencies["yearn-vaults"]["master"].VaultV3.at(event[0].vault)

    assert len(event) == 1
    assert event[0].asset == asset.address
    assert event[0].vault == new_vault
    assert event[0].releaseVersion == 0

    # make sure the vault is set up correctly
    assert new_vault.name() == name
    assert new_vault.symbol() == symbol
    assert new_vault.role_manager() == daddy
    assert new_vault.profitMaxUnlockTime() == WEEK

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.assets(0) == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.numEndorsedVaultsByVersion(asset, 0) == 1
    assert registry.getEndorsedVaults(asset)[0] == new_vault.address
    assert registry.getEndorsedVaultsByVersion(asset, 0)[0] == new_vault.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == new_vault.address
    assert registry.info(new_vault.address).asset == asset.address
    assert registry.info(new_vault.address).releaseVersion == 0
    assert registry.info(new_vault.address).deploymentTimeStamp == block


def test__endorse_deployed_vault(registry, daddy):
    pass


def test__endorse_deployed_strategy(registry, daddy):
    pass


def test__deploy_vault_with_new_release(registry, release_registry, daddy):
    pass


def test_access(registry, daddy, user):
    pass


def test__transfer_governance(registry, daddy, user):
    pass
