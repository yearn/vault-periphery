import ape
from ape import project, chain
from utils.constants import WEEK, ZERO_ADDRESS
import pytest


def add_new_release(release_registry, factory, owner):
    txs = release_registry.newRelease(factory.address, sender=owner)

    event = list(txs.decode_logs(release_registry.NewRelease))

    assert len(event) == 1
    assert event[0].factory == factory
    assert event[0].apiVersion == factory.apiVersion()


def test__set_up(registry, asset, release_registry, daddy):
    assert registry.governance() == daddy
    assert registry.releaseRegistry() == release_registry
    assert registry.numAssets() == 0
    assert registry.numEndorsedVaults(asset) == 0


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

    # address = tx.return_value
    # new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(address)
    block = tx.timestamp

    event = list(tx.decode_logs(registry.NewEndorsedVault))
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault
    )

    assert len(event) == 1
    assert event[0].asset == asset.address
    assert event[0].vault == new_vault
    assert event[0].releaseVersion == 0
    assert event[0].vaultType == registry.MULTI_STRATEGY_TYPE()

    # make sure the vault is set up correctly
    assert new_vault.name() == name
    assert new_vault.symbol() == symbol
    assert new_vault.role_manager() == daddy
    assert new_vault.profitMaxUnlockTime() == WEEK

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == new_vault.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == new_vault.address
    assert registry.vaultInfo(new_vault.address).asset == asset.address
    assert registry.vaultInfo(new_vault.address).releaseVersion == 0
    assert registry.vaultInfo(new_vault.address).deploymentTimestamp == block
    assert (
        registry.vaultInfo(new_vault.address).vaultType
        == registry.MULTI_STRATEGY_TYPE()
    )


def test__endorse_deployed_vault(
    registry, asset, release_registry, vault_factory, daddy
):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    name = "New vaults"
    symbol = "yvTest"

    # Deploy a new vault
    tx = vault_factory.deploy_new_vault(asset, name, symbol, daddy, WEEK, sender=daddy)

    block = tx.timestamp

    event = list(tx.decode_logs(vault_factory.NewVault))
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault_address
    )

    # Endorse vault
    tx = registry.endorseVault(
        new_vault.address, 0, registry.MULTI_STRATEGY_TYPE(), block, sender=daddy
    )

    event = list(tx.decode_logs(registry.NewEndorsedVault))

    assert len(event) == 1
    assert event[0].vault == new_vault.address
    assert event[0].asset == asset.address
    assert event[0].releaseVersion == 0
    assert event[0].vaultType == registry.MULTI_STRATEGY_TYPE()

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == new_vault.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == new_vault.address
    assert registry.vaultInfo(new_vault.address).asset == asset.address
    assert registry.vaultInfo(new_vault.address).releaseVersion == 0
    assert (
        registry.vaultInfo(new_vault.address).vaultType
        == registry.MULTI_STRATEGY_TYPE()
    )
    assert registry.vaultInfo(new_vault.address).deploymentTimestamp == block


def test__endorse_deployed_vault__default_values(
    registry, asset, release_registry, vault_factory, daddy
):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    name = "New vaults"
    symbol = "yvTest"

    # Deploy a new vault
    tx = vault_factory.deploy_new_vault(asset, name, symbol, daddy, WEEK, sender=daddy)

    event = list(tx.decode_logs(vault_factory.NewVault))
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault_address
    )

    # Endorse vault
    tx = registry.endorseMultiStrategyVault(new_vault.address, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))

    assert len(event) == 1
    assert event[0].vault == new_vault.address
    assert event[0].asset == asset.address
    assert event[0].releaseVersion == 0
    assert event[0].vaultType == registry.MULTI_STRATEGY_TYPE()

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == new_vault.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == new_vault.address
    assert registry.vaultInfo(new_vault.address).asset == asset.address
    assert registry.vaultInfo(new_vault.address).releaseVersion == 0
    assert (
        registry.vaultInfo(new_vault.address).vaultType
        == registry.MULTI_STRATEGY_TYPE()
    )
    assert registry.vaultInfo(new_vault.address).deploymentTimestamp == 0


def test__endorse_deployed_strategy(
    registry, asset, release_registry, vault_factory, strategy, daddy, chain
):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    block = chain.pending_timestamp - 1
    tx = registry.endorseVault(
        strategy, 0, registry.SINGLE_STRATEGY_TYPE(), block, sender=daddy
    )

    event = list(tx.decode_logs(registry.NewEndorsedVault))

    assert len(event) == 1
    assert event[0].vault == strategy.address
    assert event[0].asset == asset.address
    assert event[0].releaseVersion == 0
    assert event[0].vaultType == registry.SINGLE_STRATEGY_TYPE()

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == strategy.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == strategy.address
    assert registry.vaultInfo(strategy.address).asset == asset.address
    assert registry.vaultInfo(strategy.address).releaseVersion == 0
    assert (
        registry.vaultInfo(strategy.address).vaultType
        == registry.SINGLE_STRATEGY_TYPE()
    )
    assert registry.vaultInfo(strategy.address).deploymentTimestamp == block


def test__endorse_deployed_strategy__default_values(
    registry, asset, release_registry, vault_factory, strategy, daddy, chain
):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    tx = registry.endorseSingleStrategyVault(strategy, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))

    assert len(event) == 1
    assert event[0].vault == strategy.address
    assert event[0].asset == asset.address
    assert event[0].releaseVersion == 0
    assert event[0].vaultType == registry.SINGLE_STRATEGY_TYPE()

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == strategy.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == strategy.address
    assert registry.vaultInfo(strategy.address).asset == asset.address
    assert registry.vaultInfo(strategy.address).releaseVersion == 0
    assert (
        registry.vaultInfo(strategy.address).vaultType
        == registry.SINGLE_STRATEGY_TYPE()
    )
    assert registry.vaultInfo(strategy.address).deploymentTimestamp == 0


def test__deploy_vault_with_new_release(
    registry, asset, release_registry, vault_factory, daddy
):
    # Add a mock factory for version release 1
    mock_factory = daddy.deploy(project.MockFactory, "6.9")
    add_new_release(
        release_registry=release_registry, factory=mock_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    # Set the factory as the second release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 2

    name = "New vaults"
    symbol = "yvTest"

    # Deploy a new vault
    tx = registry.newEndorsedVault(asset, name, symbol, daddy, WEEK, 0, sender=daddy)

    # address = tx.return_value
    # new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(address)
    block = tx.timestamp

    event = list(tx.decode_logs(registry.NewEndorsedVault))
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault
    )

    assert len(event) == 1
    assert event[0].asset == asset.address
    assert event[0].vault == new_vault
    assert event[0].releaseVersion == 1
    assert event[0].vaultType == registry.MULTI_STRATEGY_TYPE()

    # make sure the vault is set up correctly
    assert new_vault.name() == name
    assert new_vault.symbol() == symbol
    assert new_vault.role_manager() == daddy
    assert new_vault.profitMaxUnlockTime() == WEEK

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == new_vault.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == new_vault.address
    assert registry.vaultInfo(new_vault.address).asset == asset.address
    assert registry.vaultInfo(new_vault.address).releaseVersion == 1
    assert (
        registry.vaultInfo(new_vault.address).vaultType
        == registry.MULTI_STRATEGY_TYPE()
    )
    assert registry.vaultInfo(new_vault.address).deploymentTimestamp == block


def test__deploy_vault_with_old_release(
    registry, asset, release_registry, vault_factory, daddy
):
    # Set the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    # Add a mock factory for version release 2
    mock_factory = daddy.deploy(project.MockFactory, "6.9")
    add_new_release(
        release_registry=release_registry, factory=mock_factory, owner=daddy
    )

    assert release_registry.numReleases() == 2

    name = "New vaults"
    symbol = "yvTest"

    # Deploy a new vault offset of 1
    tx = registry.newEndorsedVault(asset, name, symbol, daddy, WEEK, 1, sender=daddy)

    # address = tx.return_value
    # new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(address)
    block = tx.timestamp

    event = list(tx.decode_logs(registry.NewEndorsedVault))
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault
    )

    assert len(event) == 1
    assert event[0].asset == asset.address
    assert event[0].vault == new_vault
    assert event[0].releaseVersion == 0
    assert event[0].vaultType == registry.MULTI_STRATEGY_TYPE()

    # make sure the vault is set up correctly
    assert new_vault.name() == name
    assert new_vault.symbol() == symbol
    assert new_vault.role_manager() == daddy
    assert new_vault.profitMaxUnlockTime() == WEEK

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == new_vault.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == new_vault.address
    assert registry.vaultInfo(new_vault.address).asset == asset.address
    assert registry.vaultInfo(new_vault.address).releaseVersion == 0
    assert (
        registry.vaultInfo(new_vault.address).vaultType
        == registry.MULTI_STRATEGY_TYPE()
    )
    assert registry.vaultInfo(new_vault.address).deploymentTimestamp == block


def test__endorse_deployed_vault_wrong_api__reverts(
    registry, asset, release_registry, vault_factory, daddy
):
    # Add a mock factory for version release 1
    mock_factory = daddy.deploy(project.MockFactory, "6.9")
    add_new_release(
        release_registry=release_registry, factory=mock_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    # Set the factory as the second release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 2

    name = "New vaults"
    symbol = "yvTest"

    # Deploy a new vault
    tx = vault_factory.deploy_new_vault(asset, name, symbol, daddy, WEEK, sender=daddy)

    event = list(tx.decode_logs(vault_factory.NewVault))
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault_address
    )

    # Endorse vault with incorrect api version
    with ape.reverts("Wrong API Version"):
        registry.endorseVault(new_vault, 1, 1, 0, sender=daddy)

    registry.endorseVault(new_vault, 0, registry.MULTI_STRATEGY_TYPE(), 0, sender=daddy)


def test__endorse_strategy_wrong_api__reverts(
    registry, asset, strategy, release_registry, vault_factory, daddy
):
    # Add a mock factory for version release 1
    mock_factory = daddy.deploy(project.MockFactory, "6.9")
    add_new_release(
        release_registry=release_registry, factory=mock_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    # Set the factory as the second release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 2

    # Endorse vault with incorrect api version
    with ape.reverts("Wrong API Version"):
        registry.endorseVault(
            strategy, 1, registry.SINGLE_STRATEGY_TYPE(), 0, sender=daddy
        )

    registry.endorseVault(strategy, 0, registry.SINGLE_STRATEGY_TYPE(), 0, sender=daddy)


def test__tag_vault(registry, asset, release_registry, vault_factory, daddy, strategy):
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    name = "New vaults"
    symbol = "yvTest"

    # Deploy a new vault offset of 1
    tx = registry.newEndorsedVault(asset, name, symbol, daddy, WEEK, 0, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))
    vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(event[0].vault)

    # Make sure it is endorsed but not tagged.
    assert registry.vaultInfo(vault.address).asset == asset.address
    assert registry.vaultInfo(vault.address).tag == ""

    tag = "Test Tag"

    registry.tagVault(vault.address, tag, sender=daddy)

    assert registry.vaultInfo(vault.address).asset == asset.address
    assert registry.vaultInfo(vault.address).tag == tag

    # Try to tag an un endorsed vault
    with ape.reverts("!Endorsed"):
        registry.tagVault(strategy.address, tag, sender=daddy)

    # Endorse the strategy then tag it.
    registry.endorseSingleStrategyVault(strategy.address, sender=daddy)

    assert registry.vaultInfo(strategy.address).asset == asset.address
    assert registry.vaultInfo(strategy.address).tag == ""

    tag = "Test Tag"

    registry.tagVault(strategy.address, tag, sender=daddy)

    assert registry.vaultInfo(strategy.address).asset == asset.address
    assert registry.vaultInfo(strategy.address).tag == tag


def test__remove_vault(registry, asset, release_registry, vault_factory, daddy):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    name = "New vaults"
    symbol = "yvTest"

    # Deploy a new vault
    tx = registry.newEndorsedVault(asset, name, symbol, daddy, WEEK, 0, sender=daddy)

    # address = tx.return_value
    # new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(address)
    block = tx.timestamp

    event = list(tx.decode_logs(registry.NewEndorsedVault))
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault
    )

    assert len(event) == 1
    assert event[0].asset == asset.address
    assert event[0].vault == new_vault
    assert event[0].vaultType == registry.MULTI_STRATEGY_TYPE()
    assert event[0].releaseVersion == 0

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == new_vault.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == new_vault.address
    assert registry.vaultInfo(new_vault.address).asset == asset.address
    assert registry.vaultInfo(new_vault.address).releaseVersion == 0
    assert (
        registry.vaultInfo(new_vault.address).vaultType
        == registry.MULTI_STRATEGY_TYPE()
    )
    assert registry.vaultInfo(new_vault.address).deploymentTimestamp == block

    # Remove the vault
    tx = registry.removeVault(new_vault, 0, sender=daddy)

    event = list(tx.decode_logs(registry.RemovedVault))

    assert len(event) == 1
    assert event[0].vault == new_vault.address
    assert event[0].asset == asset.address
    assert event[0].releaseVersion == 0
    assert event[0].vaultType == registry.MULTI_STRATEGY_TYPE()

    # Make sure it was removed
    assert registry.numAssets() == 1
    assert registry.getAssets() == [asset.address]
    assert registry.numEndorsedVaults(asset) == 0
    assert registry.getEndorsedVaults(asset) == []
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert all_vaults[0] == []
    assert registry.vaultInfo(new_vault.address).asset == ZERO_ADDRESS
    assert registry.vaultInfo(new_vault.address).releaseVersion == 0
    assert registry.vaultInfo(new_vault.address).deploymentTimestamp == 0
    assert registry.vaultInfo(new_vault.address).vaultType == 0
    assert registry.vaultInfo(new_vault.address).tag == ""


def test__remove_vault__two_vaults(
    registry, asset, release_registry, vault_factory, daddy
):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    name = "New vaults"
    symbol = "yvTest"

    # Deploy a new vault
    tx = registry.newEndorsedVault(asset, name, symbol, daddy, WEEK, 0, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault
    )

    tx = registry.newEndorsedVault(
        asset, "second Vault", "sec", daddy, WEEK, 0, sender=daddy
    )

    event = list(tx.decode_logs(registry.NewEndorsedVault))
    second_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault
    )

    # Make sure they are endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 2
    assert registry.getEndorsedVaults(asset) == [
        new_vault.address,
        second_vault.address,
    ]
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 2
    assert all_vaults[0] == [new_vault.address, second_vault.address]
    assert registry.vaultInfo(new_vault.address).asset == asset.address
    assert registry.vaultInfo(new_vault.address).releaseVersion == 0
    assert registry.vaultInfo(second_vault.address).asset == asset.address
    assert registry.vaultInfo(second_vault.address).releaseVersion == 0

    # Remove the first vault
    tx = registry.removeVault(new_vault, 0, sender=daddy)

    event = list(tx.decode_logs(registry.RemovedVault))

    assert len(event) == 1
    assert event[0].vault == new_vault.address
    assert event[0].asset == asset.address
    assert event[0].releaseVersion == 0

    # Make sure the second is still endorsed
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == second_vault.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == second_vault.address
    assert registry.vaultInfo(new_vault.address).asset == ZERO_ADDRESS
    assert registry.vaultInfo(new_vault.address).releaseVersion == 0
    assert registry.vaultInfo(new_vault.address).tag == ""
    assert registry.vaultInfo(second_vault.address).asset == asset.address
    assert registry.vaultInfo(second_vault.address).releaseVersion == 0


def test__remove_strategy(
    registry, asset, release_registry, vault_factory, strategy, daddy
):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    tx = registry.endorseSingleStrategyVault(strategy, sender=daddy)

    event = list(tx.decode_logs(registry.NewEndorsedVault))
    assert len(event) == 1
    assert event[0].asset == asset.address
    assert event[0].vault == strategy
    assert event[0].releaseVersion == 0

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == strategy.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == strategy.address
    assert registry.vaultInfo(strategy.address).asset == asset.address
    assert registry.vaultInfo(strategy.address).releaseVersion == 0
    assert (
        registry.vaultInfo(strategy.address).vaultType
        == registry.SINGLE_STRATEGY_TYPE()
    )

    # Remove the strategy
    tx = registry.removeVault(strategy, 0, sender=daddy)

    event = list(tx.decode_logs(registry.RemovedVault))

    assert len(event) == 1
    assert event[0].vault == strategy.address
    assert event[0].asset == asset.address
    assert event[0].releaseVersion == 0

    # Make sure it was removed
    assert registry.numAssets() == 1
    assert registry.getAssets() == [asset.address]
    assert registry.numEndorsedVaults(asset) == 0
    assert registry.getEndorsedVaults(asset) == []
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert all_vaults[0] == []
    assert registry.vaultInfo(strategy.address).asset == ZERO_ADDRESS
    assert registry.vaultInfo(strategy.address).releaseVersion == 0
    assert registry.vaultInfo(strategy.address).deploymentTimestamp == 0
    assert registry.vaultInfo(strategy.address).vaultType == 0
    assert registry.vaultInfo(strategy.address).tag == ""


def test__remove_strategy__two_strategies(
    registry, asset, release_registry, vault_factory, strategy, create_strategy, daddy
):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    registry.endorseSingleStrategyVault(strategy, sender=daddy)

    second_strategy = create_strategy()
    registry.endorseSingleStrategyVault(second_strategy, sender=daddy)

    # Make sure they are endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 2
    assert registry.getEndorsedVaults(asset) == [
        strategy.address,
        second_strategy.address,
    ]
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 2
    assert all_vaults[0] == [strategy.address, second_strategy.address]
    assert registry.vaultInfo(strategy.address).asset == asset.address
    assert registry.vaultInfo(strategy.address).releaseVersion == 0
    assert registry.vaultInfo(second_strategy.address).asset == asset.address
    assert registry.vaultInfo(second_strategy.address).releaseVersion == 0
    assert (
        registry.vaultInfo(second_strategy.address).vaultType
        == registry.SINGLE_STRATEGY_TYPE()
    )

    # Remove the first strategy
    tx = registry.removeVault(strategy, 0, sender=daddy)

    event = list(tx.decode_logs(registry.RemovedVault))

    assert len(event) == 1
    assert event[0].vault == strategy.address
    assert event[0].asset == asset.address
    assert event[0].releaseVersion == 0

    # Make sure the second is still endorsed
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == second_strategy.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == second_strategy.address
    assert registry.vaultInfo(strategy.address).asset == ZERO_ADDRESS
    assert registry.vaultInfo(strategy.address).releaseVersion == 0
    assert registry.vaultInfo(strategy.address).vaultType == 0
    assert registry.vaultInfo(strategy.address).tag == ""
    assert registry.vaultInfo(second_strategy.address).asset == asset.address
    assert registry.vaultInfo(second_strategy.address).releaseVersion == 0
    assert (
        registry.vaultInfo(second_strategy.address).vaultType
        == registry.SINGLE_STRATEGY_TYPE()
    )


def test__remove_asset(
    registry, asset, release_registry, vault_factory, strategy, create_strategy, daddy
):
    # Add the factory as the first release
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    assert release_registry.numReleases() == 1

    registry.endorseSingleStrategyVault(strategy, sender=daddy)

    # Make sure it was endorsed correctly
    assert registry.numAssets() == 1
    assert registry.getAssets()[0] == asset.address
    assert registry.numEndorsedVaults(asset) == 1
    assert registry.getEndorsedVaults(asset)[0] == strategy.address
    all_vaults = registry.getAllEndorsedVaults()
    assert len(all_vaults) == 1
    assert len(all_vaults[0]) == 1
    assert all_vaults[0][0] == strategy.address
    assert registry.vaultInfo(strategy.address).asset == asset.address
    assert registry.vaultInfo(strategy.address).releaseVersion == 0

    # Should not be able to remove the asset
    with ape.reverts("still in use"):
        registry.removeAsset(asset.address, 0, sender=daddy)

    # Remove the strategy
    registry.removeVault(strategy.address, 0, sender=daddy)

    registry.removeAsset(asset.address, 0, sender=daddy)

    assert registry.numAssets() == 0
    assert registry.getAssets() == []
    assert registry.assetIsUsed(asset.address) == False


def test__access(
    registry, asset, release_registry, vault_factory, daddy, strategy, user
):
    add_new_release(
        release_registry=release_registry, factory=vault_factory, owner=daddy
    )

    name = "New vaults"
    symbol = "yvTest"

    # Cant deploy a vault through registry
    with ape.reverts("!governance"):
        registry.newEndorsedVault(asset, name, symbol, daddy, WEEK, 0, sender=user)

    # Deploy a new vault
    tx = vault_factory.deploy_new_vault(asset, name, symbol, daddy, WEEK, sender=daddy)

    event = list(tx.decode_logs(vault_factory.NewVault))
    new_vault = project.dependencies["yearn-vaults"]["v3.0.1"].VaultV3.at(
        event[0].vault_address
    )

    # Cant endorse a vault
    with ape.reverts("!governance"):
        registry.endorseVault(new_vault, 0, 1, 0, sender=user)

    # cant endorse vault with default values
    with ape.reverts("!governance"):
        registry.endorseMultiStrategyVault(new_vault, sender=user)

    # cant endorse strategy with default values
    with ape.reverts("!governance"):
        registry.endorseSingleStrategyVault(strategy, sender=user)

    with ape.reverts("!governance"):
        registry.tagVault(strategy, "tag", sender=user)

    with ape.reverts("!governance"):
        registry.removeVault(new_vault.address, 0, sender=user)

    with ape.reverts("!governance"):
        registry.removeAsset(asset.address, 0, sender=user)

    # cant transfer governance
    with ape.reverts("!governance"):
        registry.transferGovernance(user, sender=user)


def test__transfer_governance(registry, daddy, user):
    assert registry.governance() == daddy

    with ape.reverts("ZERO ADDRESS"):
        registry.transferGovernance(ZERO_ADDRESS, sender=daddy)

    assert registry.governance() == daddy

    tx = registry.transferGovernance(user, sender=daddy)

    event = list(tx.decode_logs(registry.GovernanceTransferred))

    assert len(event) == 1
    assert event[0].previousGovernance == daddy
    assert event[0].newGovernance == user
    assert registry.governance() == user
