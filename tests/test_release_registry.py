import ape
from ape import project
from utils.constants import ZERO_ADDRESS
import pytest


def test__deployment(release_registry, daddy):
    assert release_registry.governance() == daddy
    assert release_registry.numReleases() == 0
    assert release_registry.factories(0) == ZERO_ADDRESS
    assert release_registry.releaseTargets("3.0.1") == 0


def test_new_release(release_registry, daddy, vault_factory):
    assert release_registry.numReleases() == 0
    assert release_registry.factories(0) == ZERO_ADDRESS

    tx = release_registry.newRelease(vault_factory.address, sender=daddy)

    event = list(tx.decode_logs(release_registry.NewRelease))

    assert len(event) == 1
    assert event[0].releaseId == 0
    assert event[0].factory == vault_factory
    assert event[0].apiVersion == vault_factory.apiVersion()

    assert release_registry.numReleases() == 1
    assert release_registry.factories(0) == vault_factory.address
    assert release_registry.releaseTargets(vault_factory.apiVersion()) == 0
    assert release_registry.latestFactory() == vault_factory.address
    assert release_registry.latestRelease() == vault_factory.apiVersion()

    new_api = "4.3.2"
    # Deploy a new mock factory with a different api
    new_factory = daddy.deploy(project.MockFactory, new_api)

    tx = release_registry.newRelease(new_factory.address, sender=daddy)

    event = list(tx.decode_logs(release_registry.NewRelease))

    assert len(event) == 1
    assert event[0].releaseId == 1
    assert event[0].factory == new_factory.address
    assert event[0].apiVersion == new_api

    assert release_registry.numReleases() == 2
    assert release_registry.factories(1) == new_factory.address
    assert release_registry.releaseTargets(new_factory.apiVersion()) == 1
    assert release_registry.latestFactory() == new_factory.address
    assert release_registry.latestRelease() == new_api

    # make sure the first factory is still returning
    assert release_registry.factories(0) == vault_factory.address
    assert release_registry.releaseTargets(vault_factory.apiVersion()) == 0


def test_access(release_registry, daddy, user, vault_factory):
    assert release_registry.numReleases() == 0
    assert release_registry.factories(0) == ZERO_ADDRESS

    # only daddy should be able to set a new release
    with ape.reverts():
        release_registry.newRelease(vault_factory.address, sender=user)

    assert release_registry.numReleases() == 0
    assert release_registry.factories(0) == ZERO_ADDRESS

    release_registry.newRelease(vault_factory.address, sender=daddy)

    assert release_registry.numReleases() == 1
    assert release_registry.factories(0) == vault_factory.address


def test__add_same_factory(release_registry, daddy, vault_factory):
    assert release_registry.numReleases() == 0
    assert release_registry.factories(0) == ZERO_ADDRESS

    tx = release_registry.newRelease(vault_factory.address, sender=daddy)

    event = list(tx.decode_logs(release_registry.NewRelease))

    assert len(event) == 1
    assert event[0].releaseId == 0
    assert event[0].factory == vault_factory
    assert event[0].apiVersion == vault_factory.apiVersion()

    assert release_registry.numReleases() == 1
    assert release_registry.factories(0) == vault_factory.address
    assert release_registry.latestFactory() == vault_factory.address
    assert release_registry.latestRelease() == vault_factory.apiVersion()

    with ape.reverts("ReleaseRegistry: same api version"):
        release_registry.newRelease(vault_factory.address, sender=daddy)

    assert release_registry.numReleases() == 1


def test__transfer_governance(release_registry, daddy, user):
    assert release_registry.governance() == daddy

    with ape.reverts("ZERO ADDRESS"):
        release_registry.transferGovernance(ZERO_ADDRESS, sender=daddy)

    assert release_registry.governance() == daddy

    tx = release_registry.transferGovernance(user, sender=daddy)

    event = list(tx.decode_logs(release_registry.GovernanceTransferred))

    assert len(event) == 1
    assert event[0].previousGovernance == daddy
    assert event[0].newGovernance == user
    assert release_registry.governance() == user
