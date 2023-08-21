import ape
from ape import chain, project
from utils.constants import ZERO_ADDRESS, MAX_INT


def test_setup(generic_debt_allocator_factory, user, strategy, vault):
    tx = generic_debt_allocator_factory.newGenericDebtAllocator(
        vault, user, sender=user
    )

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
        generic_debt_allocator.setMinimumChange(strategy, minimum, sender=user)

    with ape.reverts("!active"):
        generic_debt_allocator.setMinimumChange(strategy, minimum, sender=daddy)

    vault.add_strategy(strategy.address, sender=daddy)

    tx = generic_debt_allocator.setMinimumChange(strategy, minimum, sender=daddy)

    event = list(tx.decode_logs(generic_debt_allocator.SetMinimumChange))[0]

    assert event.strategy == strategy.address
    assert event.minimumChange == minimum
    assert generic_debt_allocator.configs(strategy) == (0, minimum)


def test_set_minimum(generic_debt_allocator, daddy, vault, strategy, user):
    assert generic_debt_allocator.configs(strategy) == (0, 0)

    minimum = int(1e17)
    target = int(5_000)

    with ape.reverts("!governance"):
        generic_debt_allocator.setTargetDebtRatio(strategy, target, sender=user)

    with ape.reverts("!active"):
        generic_debt_allocator.setTargetDebtRatio(strategy, target, sender=daddy)

    vault.add_strategy(strategy.address, sender=daddy)

    with ape.reverts("!minimum"):
        generic_debt_allocator.setTargetDebtRatio(strategy, target, sender=daddy)

    generic_debt_allocator.setMinimumChange(strategy, minimum, sender=daddy)

    with ape.reverts("ratio too high"):
        generic_debt_allocator.setTargetDebtRatio(strategy, int(10_001), sender=daddy)

    tx = generic_debt_allocator.setTargetDebtRatio(strategy, target, sender=daddy)

    event = list(tx.decode_logs(generic_debt_allocator.SetTargetDebtRatio))[0]

    assert event.strategy == strategy.address
    assert event.targetRatio == target
    assert event.totalDebtRatio == target
    assert generic_debt_allocator.debtRatio() == target
    assert generic_debt_allocator.configs(strategy) == (target, minimum)


def test_should_update_debt(
    generic_debt_allocator, vault, strategy, daddy, deposit_into_vault, amount
):
    assert generic_debt_allocator.configs(strategy.address) == (0, 0)

    with ape.reverts("!active"):
        generic_debt_allocator.shouldUpdateDebt(strategy.address)

    vault.add_strategy(strategy.address, sender=daddy)

    with ape.reverts("no targetRatio"):
        generic_debt_allocator.shouldUpdateDebt(strategy.address)

    minimum = int(1)
    target = int(5_000)

    generic_debt_allocator.setMinimumChange(strategy, minimum, sender=daddy)
    generic_debt_allocator.setTargetDebtRatio(strategy, target, sender=daddy)

    # Vault has no assets so should be false.
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    deposit_into_vault(vault, amount)

    # No max debt has been set so should be false.
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    # Should now want to allocate 50%
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    print("got", bytes)
    print("Made ", vault.update_debt.encode_input(strategy.address, amount // 2))
    assert bytes == vault.update_debt.encode_input(strategy.address, amount // 2)

    vault.update_debt(strategy, amount // 2, sender=daddy)

    # Should now be false again once allocated
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Update the ratio to make true
    generic_debt_allocator.setTargetDebtRatio(strategy, int(target + 1), sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(
        strategy.address, int(amount * 5_001 // 10_000)
    )

    # Lower the max debt so its == to current debt
    vault.update_max_debt_for_strategy(strategy, int(amount // 2), sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Reset it.
    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(
        strategy.address, int(amount * 5_001 // 10_000)
    )

    # Increase the minimum_total_idle
    vault.set_minimum_total_idle(vault.totalIdle(), sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("No Idle").encode("utf-8")

    vault.set_minimum_total_idle(0, sender=daddy)

    # increase the minimum so its false again
    generic_debt_allocator.setMinimumChange(strategy, int(1e30), sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Lower the target and minimum
    generic_debt_allocator.setMinimumChange(strategy, int(1), sender=daddy)
    generic_debt_allocator.setTargetDebtRatio(strategy, int(target // 2), sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy.address, amount // 4)
