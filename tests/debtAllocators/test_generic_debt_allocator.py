import ape
from ape import chain, project
from utils.constants import ZERO_ADDRESS, MAX_INT, ROLES


def test_setup(generic_debt_allocator_factory, user, strategy, vault):
    tx = generic_debt_allocator_factory.newGenericDebtAllocator(
        vault, user, 0, sender=user
    )

    events = list(tx.decode_logs(generic_debt_allocator_factory.NewDebtAllocator))

    assert len(events) == 1
    assert events[0].vault == vault.address

    generic_debt_allocator = project.GenericDebtAllocator.at(events[0].allocator)

    assert generic_debt_allocator.governance() == user
    assert generic_debt_allocator.keepers(user) == True
    assert generic_debt_allocator.vault() == vault.address
    assert generic_debt_allocator.getConfig(strategy) == (0, 0, 0, 0)
    assert generic_debt_allocator.totalDebtRatio() == 0
    with ape.reverts("!active"):
        generic_debt_allocator.shouldUpdateDebt(strategy)


def test_set_keepers(generic_debt_allocator, daddy, vault, strategy, user):
    assert generic_debt_allocator.keepers(daddy) == True
    assert generic_debt_allocator.keepers(user) == False

    with ape.reverts("!governance"):
        generic_debt_allocator.setKeeper(user, True, sender=user)

    tx = generic_debt_allocator.setKeeper(user, True, sender=daddy)

    event = list(tx.decode_logs(generic_debt_allocator.UpdateKeeper))[0]

    assert event.keeper == user
    assert event.allowed == True
    assert generic_debt_allocator.keepers(user) == True

    tx = generic_debt_allocator.setKeeper(daddy, False, sender=daddy)

    event = list(tx.decode_logs(generic_debt_allocator.UpdateKeeper))[0]

    assert event.keeper == daddy
    assert event.allowed == False
    assert generic_debt_allocator.keepers(daddy) == False


def test_set_minimum_change(generic_debt_allocator, daddy, vault, strategy, user):
    assert generic_debt_allocator.getConfig(strategy) == (0, 0, 0, 0)
    assert generic_debt_allocator.minimumChange() == 0

    minimum = int(1e17)

    with ape.reverts("!governance"):
        generic_debt_allocator.setMinimumChange(minimum, sender=user)

    with ape.reverts("zero"):
        generic_debt_allocator.setMinimumChange(0, sender=daddy)

    tx = generic_debt_allocator.setMinimumChange(minimum, sender=daddy)

    event = list(tx.decode_logs(generic_debt_allocator.UpdateMinimumChange))[0]

    assert event.newMinimumChange == minimum
    assert generic_debt_allocator.minimumChange() == minimum


def test_set_minimum_wait(generic_debt_allocator, daddy, vault, strategy, user):
    assert generic_debt_allocator.getConfig(strategy) == (0, 0, 0, 0)
    assert generic_debt_allocator.minimumWait() == 0

    minimum = int(1e17)

    with ape.reverts("!governance"):
        generic_debt_allocator.setMinimumWait(minimum, sender=user)

    tx = generic_debt_allocator.setMinimumWait(minimum, sender=daddy)

    event = list(tx.decode_logs(generic_debt_allocator.UpdateMinimumWait))[0]

    assert event.newMinimumWait == minimum
    assert generic_debt_allocator.minimumWait() == minimum


def test_set_max_debt_update_loss(generic_debt_allocator, daddy, vault, strategy, user):
    assert generic_debt_allocator.getConfig(strategy) == (0, 0, 0, 0)
    assert generic_debt_allocator.maxDebtUpdateLoss() == 1

    max = int(69)

    with ape.reverts("!governance"):
        generic_debt_allocator.setMaxDebtUpdateLoss(max, sender=user)

    with ape.reverts("higher than max"):
        generic_debt_allocator.setMaxDebtUpdateLoss(10_001, sender=daddy)

    tx = generic_debt_allocator.setMaxDebtUpdateLoss(max, sender=daddy)

    event = list(tx.decode_logs(generic_debt_allocator.UpdateMaxDebtUpdateLoss))[0]

    assert event.newMaxDebtUpdateLoss == max
    assert generic_debt_allocator.maxDebtUpdateLoss() == max


def test_set_ratios(
    generic_debt_allocator, daddy, vault, strategy, create_strategy, user
):
    assert generic_debt_allocator.getConfig(strategy) == (0, 0, 0, 0)

    minimum = int(1e17)
    max = int(6_000)
    target = int(5_000)

    with ape.reverts("!keeper"):
        generic_debt_allocator.setStrategyDebtRatio(strategy, target, max, sender=user)

    vault.add_strategy(strategy.address, sender=daddy)

    with ape.reverts("!minimum"):
        generic_debt_allocator.setStrategyDebtRatio(strategy, target, max, sender=daddy)

    generic_debt_allocator.setMinimumChange(minimum, sender=daddy)

    with ape.reverts("max too high"):
        generic_debt_allocator.setStrategyDebtRatio(
            strategy, target, int(10_001), sender=daddy
        )

    with ape.reverts("max ratio"):
        generic_debt_allocator.setStrategyDebtRatio(
            strategy, int(max + 1), max, sender=daddy
        )

    tx = generic_debt_allocator.setStrategyDebtRatio(
        strategy, target, max, sender=daddy
    )

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_debt_allocator.totalDebtRatio() == target
    assert generic_debt_allocator.getConfig(strategy) == (target, max, 0, 0)

    new_strategy = create_strategy()
    vault.add_strategy(new_strategy, sender=daddy)
    with ape.reverts("ratio too high"):
        generic_debt_allocator.setStrategyDebtRatio(
            new_strategy, int(10_000), int(10_000), sender=daddy
        )

    target = int(8_000)
    tx = generic_debt_allocator.setStrategyDebtRatio(strategy, target, sender=daddy)

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == target * 1.1
    assert event.newTotalDebtRatio == target
    assert generic_debt_allocator.totalDebtRatio() == target
    assert generic_debt_allocator.getConfig(strategy) == (target, target * 1.1, 0, 0)


def test_increase_debt_ratio(
    generic_debt_allocator, daddy, vault, strategy, create_strategy, user
):
    assert generic_debt_allocator.getConfig(strategy) == (0, 0, 0, 0)

    minimum = int(1e17)
    target = int(5_000)
    increase = int(5_000)
    max = target * 1.1

    with ape.reverts("!keeper"):
        generic_debt_allocator.increaseStrategyDebtRatio(
            strategy, increase, sender=user
        )

    vault.add_strategy(strategy.address, sender=daddy)

    with ape.reverts("!minimum"):
        generic_debt_allocator.increaseStrategyDebtRatio(
            strategy, increase, sender=daddy
        )

    generic_debt_allocator.setMinimumChange(minimum, sender=daddy)

    tx = generic_debt_allocator.increaseStrategyDebtRatio(
        strategy, increase, sender=daddy
    )

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_debt_allocator.totalDebtRatio() == target
    assert generic_debt_allocator.getConfig(strategy) == (target, max, 0, 0)

    new_strategy = create_strategy()
    vault.add_strategy(new_strategy, sender=daddy)

    with ape.reverts("ratio too high"):
        generic_debt_allocator.increaseStrategyDebtRatio(
            new_strategy, int(5_001), sender=daddy
        )

    target = int(8_000)
    max = target * 1.1
    increase = int(3_000)
    tx = generic_debt_allocator.increaseStrategyDebtRatio(
        strategy, increase, sender=daddy
    )

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_debt_allocator.totalDebtRatio() == target
    assert generic_debt_allocator.getConfig(strategy) == (target, max, 0, 0)

    target = int(10_000)
    max = int(10_000)
    increase = int(2_000)
    tx = generic_debt_allocator.increaseStrategyDebtRatio(
        strategy, increase, sender=daddy
    )

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_debt_allocator.totalDebtRatio() == target
    assert generic_debt_allocator.getConfig(strategy) == (target, max, 0, 0)


def test_decrease_debt_ratio(
    generic_debt_allocator, daddy, vault, strategy, create_strategy, user
):
    assert generic_debt_allocator.getConfig(strategy) == (0, 0, 0, 0)

    minimum = int(1e17)
    target = int(5_000)
    max = target * 1.1

    vault.add_strategy(strategy.address, sender=daddy)
    generic_debt_allocator.setMinimumChange(minimum, sender=daddy)

    # Underflow
    with ape.reverts():
        generic_debt_allocator.decreaseStrategyDebtRatio(strategy, target, sender=daddy)

    # Add the target
    tx = generic_debt_allocator.increaseStrategyDebtRatio(
        strategy, target, sender=daddy
    )

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_debt_allocator.totalDebtRatio() == target
    assert generic_debt_allocator.getConfig(strategy) == (target, max, 0, 0)

    target = int(2_000)
    max = target * 1.1
    decrease = int(3_000)

    with ape.reverts("!keeper"):
        generic_debt_allocator.decreaseStrategyDebtRatio(
            strategy, decrease, sender=user
        )

    tx = generic_debt_allocator.decreaseStrategyDebtRatio(
        strategy, decrease, sender=daddy
    )

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_debt_allocator.totalDebtRatio() == target
    assert generic_debt_allocator.getConfig(strategy) == (target, max, 0, 0)

    target = int(0)
    max = int(0)
    decrease = int(2_000)
    tx = generic_debt_allocator.decreaseStrategyDebtRatio(
        strategy, decrease, sender=daddy
    )

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_debt_allocator.totalDebtRatio() == target
    assert generic_debt_allocator.getConfig(strategy) == (0, 0, 0, 0)


def test_should_update_debt(
    generic_debt_allocator, vault, strategy, daddy, deposit_into_vault, amount
):
    assert generic_debt_allocator.getConfig(strategy.address) == (0, 0, 0, 0)
    vault.add_role(generic_debt_allocator, ROLES.DEBT_MANAGER, sender=daddy)

    with ape.reverts("!active"):
        generic_debt_allocator.shouldUpdateDebt(strategy.address)

    vault.add_strategy(strategy.address, sender=daddy)

    minimum = int(1)
    target = int(5_000)
    max = int(5_000)

    generic_debt_allocator.setMinimumChange(minimum, sender=daddy)
    generic_debt_allocator.setStrategyDebtRatio(strategy, target, max, sender=daddy)

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

    generic_debt_allocator.update_debt(strategy, amount // 2, sender=daddy)
    chain.mine(1)

    # Should now be false again once allocated
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Update the ratio to make true
    generic_debt_allocator.setStrategyDebtRatio(
        strategy, int(target + 1), int(target + 1), sender=daddy
    )

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(
        strategy.address, int(amount * 5_001 // 10_000)
    )

    # Set a minimumWait time
    generic_debt_allocator.setMinimumWait(MAX_INT, sender=daddy)
    # Should now be false
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("min wait").encode("utf-8")

    generic_debt_allocator.setMinimumWait(0, sender=daddy)

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
    generic_debt_allocator.setMinimumChange(int(1e30), sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Lower the target and minimum
    generic_debt_allocator.setMinimumChange(int(1), sender=daddy)
    generic_debt_allocator.setStrategyDebtRatio(
        strategy, int(target // 2), int(target // 2), sender=daddy
    )

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy.address, amount // 4)


def test_update_debt(
    generic_debt_allocator, vault, strategy, daddy, user, deposit_into_vault, amount
):
    assert generic_debt_allocator.getConfig(strategy) == (0, 0, 0, 0)
    deposit_into_vault(vault, amount)

    assert vault.totalIdle() == amount
    assert vault.totalDebt() == 0

    vault.add_strategy(strategy, sender=daddy)
    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    # This reverts by the allocator
    with ape.reverts("!keeper"):
        generic_debt_allocator.update_debt(strategy, amount, sender=user)

    # This reverts by the vault
    with ape.reverts("not allowed"):
        generic_debt_allocator.update_debt(strategy, amount, sender=daddy)

    vault.add_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )

    generic_debt_allocator.update_debt(strategy, amount, sender=daddy)

    timestamp = generic_debt_allocator.getConfig(strategy)[2]
    assert timestamp != 0
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount

    generic_debt_allocator.setKeeper(user, True, sender=daddy)

    generic_debt_allocator.update_debt(strategy, 0, sender=user)

    assert generic_debt_allocator.getConfig(strategy)[2] != timestamp
    assert vault.totalIdle() == amount
    assert vault.totalDebt() == 0
