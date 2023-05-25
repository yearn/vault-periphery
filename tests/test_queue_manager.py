import ape
from ape import project
from utils.constants import ZERO_ADDRESS, ROLES
import pytest


def test__access(vault, queue_manager, daddy, user):
    # daddy has all roles. Give user just the queue manager role.
    vault.set_role(user.address, ROLES.QUEUE_MANAGER, sender=daddy)

    queue = []

    # Make sure either address can add a queue.
    queue_manager.setQueue(vault.address, queue, sender=user)
    queue_manager.setQueue(vault.address, queue, sender=daddy)

    # Remove queue manager role from each address.
    vault.set_role(daddy.address, vault.roles(daddy.address) - 16, sender=daddy)
    vault.set_role(user.address, 0, sender=daddy)

    # Make sure neither can set the queue now.
    with ape.reverts("!gov"):
        queue_manager.setQueue(vault.address, sender=user)

    with ape.reverts("!gov"):
        queue_manager.setQueue(vault.address, sender=daddy)
