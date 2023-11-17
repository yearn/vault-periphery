import ape
from ape import project
from utils.constants import ZERO_ADDRESS
import pytest


def test__factory_set_up(registry_factory, release_registry, daddy):
    assert registry_factory.releaseRegistry() == release_registry
    assert registry_factory.name() == "Custom Vault Registry Factory"


def test__new_registry(registry_factory, release_registry, management):
    new_name = "new test registry"

    # create a new registry
    tx = registry_factory.createNewRegistry(new_name, sender=management)

    # new_registry = tx.return_value
    # new_registry = project.Registry.at(new_registry)

    event = list(tx.decode_logs(registry_factory.NewRegistry))
    new_registry = project.Registry.at(event[0].newRegistry)

    assert len(event) == 1
    assert event[0].newRegistry == new_registry
    assert event[0].governance == management
    assert event[0].name == new_name

    # make sure it is set up correctly
    assert new_registry.governance() == management
    assert new_registry.releaseRegistry() == release_registry
    assert new_registry.name() == new_name
    assert new_registry.numAssets() == 0
