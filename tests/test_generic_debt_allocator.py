import ape
from ape import chain, project
from utils.constants import ZERO_ADDRESS, MAX_INT


def test_setup(generic_debt_allocator_factory, user, strategy, vault):
    tx = generic_debt_allocator_factory.newGenericDebtAllocator(vault, user, sender=user)

    events = list(tx.decode_logs(generic_debt_allocator_factory.NewDebtAllocator))

    assert len(events) == 1
    assert events[0].vault == vault.address

    generic_debt_allocator = project.GenericDebtAllocator.at(events[0].allocator)

    assert generic_debt_allocator.governance() == user
    assert generic_debt_allocator.vault() == vault.address
    assert generic_debt_allocator.configs(strategy) == (0, 0)
    assert generic_debt_allocator.debtRatio() == 0
    with ape.reverts("!active"):
        generic_debt_allocator.shouldUpdateDebt(strategy)


def test_set_minimum(generic_debt_allocator, daddy, vault, strategy, user):
    assert generic_debt_allocator.configs(strategy) == (0, 0)

    minimum = int(1e17)

    with ape.reverts("!governance"):
        generic_debt_allocator.setMinimumChange(
            strategy, minimum, sender=user
        )

    with ape.reverts("!active"):
        generic_debt_allocator.setMinimumChange(
            strategy, minimum, sender=daddy
        )

    vault.add_strategy(strategy.address, sender=daddy)

    tx = generic_debt_allocator.setMinimumChange(
            strategy, minimum, sender=daddy
        )

    event = list(tx.decode_logs(generic_debt_allocator.SetMinimumChange))[0]

    assert event.strategy == strategy.address
    assert event.minimumChange == minimum
    assert generic_debt_allocator.configs(strategy) == (0, minimum)


def test_set_minimum(generic_debt_allocator, daddy, vault, strategy, user):
    assert generic_debt_allocator.configs(strategy) == (0, 0)

    minimum = int(1e17)
    target = int(5_000)

    with ape.reverts("!governance"):
        generic_debt_allocator.setTargetDebtRatio(
            strategy, target, sender=user
        )

    with ape.reverts("!active"):
        generic_debt_allocator.setTargetDebtRatio(
            strategy, target, sender=daddy
        )

    vault.add_strategy(strategy.address, sender=daddy)

    with ape.reverts("!minimum"):
        generic_debt_allocator.setTargetDebtRatio(
            strategy, target, sender=daddy
        )
    
    generic_debt_allocator.setMinimumChange(
            strategy, minimum, sender=daddy
        )

    with ape.reverts("!max"):
        generic_debt_allocator.setTargetDebtRatio(
            strategy, int(10_001), sender=daddy
        )

    tx = generic_debt_allocator.setTargetDebtRatio(
            strategy, target, sender=daddy
        )

    event = list(tx.decode_logs(generic_debt_allocator.SetTargetDebtRatio))[0]

    assert event.strategy == strategy.address
    assert event.targetRatio == target
    assert event.totalDebtRatio == target
    assert generic_debt_allocator.debtRatio() == target
    assert generic_debt_allocator.configs(strategy) == (target, minimum)

