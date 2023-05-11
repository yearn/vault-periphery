import ape
from ape import project
import pytest

def test_something(daddy, release_registry):
    print(f"Release Registry {release_registry.address}")
    assert False