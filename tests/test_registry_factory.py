import ape
from ape import project
from utils.constants import ZERO_ADDRESS
import pytest


def test__factory_set_up(registry_factory, release_registry, daddy):
    assert registry_factory.original() != ZERO_ADDRESS
    assert registry_factory.releaseRegistry() == release_registry

    original_registry = project.Registry.at(registry_factory.original())
    # make sure the original registry was setup correctly
    assert original_registry.governance() == daddy
    assert original_registry.releaseRegistry() == release_registry
    assert original_registry.numAssets() == 0


def test__clone_registry(registry_factory, release_registry, management):
    new_name = "new test registry"

    # create a new registry
    tx = registry_factory.createNewRegistry(new_name, sender=management)

    # new_registry = tx.return_value
    # new_registry = project.Registry.at(new_registry)

    event = list(tx.decode_logs(registry_factory.NewRegistry))
    new_registry = project.Registry.at(event[0].newRegistry)

    assert len(event) == 1
    assert event[0].newRegistry == new_registry

    # make sure it is set up correctly
    assert new_registry.governance() == management
    assert new_registry.releaseRegistry() == release_registry
    assert new_registry.name() == new_name
    assert new_registry.numAssets() == 0

    # make sure we can't re initialize the registry
    with ape.reverts("!initialized"):
        new_registry.initialize(management, "testing", management, sender=management)
