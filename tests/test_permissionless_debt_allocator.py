import ape
from ape import chain
from utils.constants import ChangeType, ZERO_ADDRESS, MAX_BPS, MAX_INT, ROLES


def test__permissionless_allocator__setup(permissionless_debt_allocator, vault):
    assert (
        vault.roles(permissionless_debt_allocator)
        == ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER
    )
