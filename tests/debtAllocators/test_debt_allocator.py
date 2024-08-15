import ape
from ape import chain, project
from utils.constants import ZERO_ADDRESS, MAX_INT, ROLES


def test_setup(debt_allocator_factory, brain, user, strategy, vault):
    tx = debt_allocator_factory.newDebtAllocator(brain, sender=user)

    events = list(tx.decode_logs(debt_allocator_factory.NewDebtAllocator))

    assert len(events) == 1
    assert events[0].governance == brain

    debt_allocator = project.DebtAllocator.at(events[0].allocator)

    assert debt_allocator.governance() == brain
    assert debt_allocator.keepers(brain) == True
    assert debt_allocator.maxAcceptableBaseFee() == MAX_INT
    assert debt_allocator.minimumWait() == 60 * 60 * 6
    assert debt_allocator.managers(brain) == False
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)
    assert debt_allocator.getVaultConfig(vault) == (False, 0, 0)
    assert debt_allocator.totalDebtRatio(vault) == 0
    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault.address, strategy.address)
    assert bool == False
    assert bytes == ("!added").encode("utf-8")


def test_set_keepers(debt_allocator, brain, user):
    assert debt_allocator.keepers(brain) == True
    assert debt_allocator.keepers(user) == False

    with ape.reverts("!governance"):
        debt_allocator.setKeeper(user, True, sender=user)

    tx = debt_allocator.setKeeper(user, True, sender=brain)

    event = list(tx.decode_logs(debt_allocator.UpdateKeeper))[0]

    assert event.keeper == user
    assert event.allowed == True
    assert debt_allocator.keepers(user) == True

    tx = debt_allocator.setKeeper(brain, False, sender=brain)

    event = list(tx.decode_logs(debt_allocator.UpdateKeeper))[0]

    assert event.keeper == brain
    assert event.allowed == False
    assert debt_allocator.keepers(brain) == False


def test_set_managers(debt_allocator, brain, user):
    assert debt_allocator.managers(brain) == False
    assert debt_allocator.managers(user) == False

    with ape.reverts("!governance"):
        debt_allocator.setManager(user, True, sender=user)

    tx = debt_allocator.setManager(user, True, sender=brain)

    event = list(tx.decode_logs(debt_allocator.UpdateManager))[0]

    assert event.manager == user
    assert event.allowed == True
    assert debt_allocator.managers(user) == True

    tx = debt_allocator.setManager(user, False, sender=brain)

    event = list(tx.decode_logs(debt_allocator.UpdateManager))[0]

    assert event.manager == user
    assert event.allowed == False
    assert debt_allocator.managers(user) == False


def test_set_minimum_change(debt_allocator, vault, brain, strategy, user):
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)
    assert debt_allocator.minimumChange(vault) == 0

    minimum = int(1e17)

    with ape.reverts("!governance"):
        debt_allocator.setMinimumChange(vault, minimum, sender=user)

    with ape.reverts("zero"):
        debt_allocator.setMinimumChange(vault, 0, sender=brain)

    tx = debt_allocator.setMinimumChange(vault, minimum, sender=brain)

    event = list(tx.decode_logs(debt_allocator.UpdateMinimumChange))[0]

    assert event.newMinimumChange == minimum
    assert event.vault == vault
    assert debt_allocator.minimumChange(vault) == minimum


def test_set_minimum_wait(debt_allocator, brain, vault, strategy, user):
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)
    assert debt_allocator.minimumWait() == 60 * 60 * 6

    minimum = int(1e17)

    with ape.reverts("!governance"):
        debt_allocator.setMinimumWait(minimum, sender=user)

    tx = debt_allocator.setMinimumWait(minimum, sender=brain)

    event = list(tx.decode_logs(debt_allocator.UpdateMinimumWait))[0]

    assert event.newMinimumWait == minimum
    assert debt_allocator.minimumWait() == minimum


def test_set_max_debt_update_loss(debt_allocator, brain, vault, strategy, user):
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)
    assert debt_allocator.maxDebtUpdateLoss() == 1

    max = int(69)

    with ape.reverts("!governance"):
        debt_allocator.setMaxDebtUpdateLoss(max, sender=user)

    with ape.reverts("higher than max"):
        debt_allocator.setMaxDebtUpdateLoss(10_001, sender=brain)

    tx = debt_allocator.setMaxDebtUpdateLoss(max, sender=brain)

    event = list(tx.decode_logs(debt_allocator.UpdateMaxDebtUpdateLoss))[0]

    assert event.newMaxDebtUpdateLoss == max
    assert debt_allocator.maxDebtUpdateLoss() == max


def test_set_ratios(
    debt_allocator, brain, daddy, vault, strategy, create_strategy, user
):
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)

    minimum = int(1e17)
    max = int(6_000)
    target = int(5_000)

    with ape.reverts("!manager"):
        debt_allocator.setStrategyDebtRatio(vault, strategy, target, max, sender=user)

    vault.add_strategy(strategy.address, sender=daddy)

    with ape.reverts("!minimum"):
        debt_allocator.setStrategyDebtRatio(vault, strategy, target, max, sender=brain)

    debt_allocator.setMinimumChange(vault, minimum, sender=brain)

    with ape.reverts("max too high"):
        debt_allocator.setStrategyDebtRatio(
            vault, strategy, target, int(10_001), sender=brain
        )

    with ape.reverts("max ratio"):
        debt_allocator.setStrategyDebtRatio(
            vault, strategy, int(max + 1), max, sender=brain
        )

    tx = debt_allocator.setStrategyDebtRatio(vault, strategy, target, max, sender=brain)

    event = list(tx.decode_logs(debt_allocator.StrategyChanged))[0]

    assert event.vault == vault
    assert event.strategy == strategy
    assert event.status == 1

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio(vault) == target
    assert debt_allocator.getStrategyConfig(vault, strategy) == (
        True,
        target,
        max,
        0,
        0,
    )

    new_strategy = create_strategy()
    vault.add_strategy(new_strategy, sender=daddy)
    with ape.reverts("ratio too high"):
        debt_allocator.setStrategyDebtRatio(
            vault, new_strategy, int(10_000), int(10_000), sender=brain
        )

    target = int(8_000)
    tx = debt_allocator.setStrategyDebtRatio(vault, strategy, target, sender=brain)

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == target * 1.2
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio() == target
    assert debt_allocator.getStrategyConfig(vault, strategy) == (
        True,
        target,
        target * 1.2,
        0,
        0,
    )


def test_increase_debt_ratio(
    debt_allocator, brain, daddy, vault, strategy, create_strategy, user
):
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)

    minimum = int(1e17)
    target = int(5_000)
    increase = int(5_000)
    max = target * 1.2

    with ape.reverts("!manager"):
        debt_allocator.increaseStrategyDebtRatio(vault, strategy, increase, sender=user)

    vault.add_strategy(strategy.address, sender=daddy)

    with ape.reverts("!minimum"):
        debt_allocator.increaseStrategyDebtRatio(
            vault, strategy, increase, sender=brain
        )

    debt_allocator.setMinimumChange(vault, minimum, sender=brain)

    tx = debt_allocator.increaseStrategyDebtRatio(
        vault, strategy, increase, sender=brain
    )

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio(vault) == target
    assert debt_allocator.getStrategyConfig(vault, strategy) == (
        True,
        target,
        max,
        0,
        0,
    )

    new_strategy = create_strategy()
    vault.add_strategy(new_strategy, sender=daddy)

    with ape.reverts("ratio too high"):
        debt_allocator.increaseStrategyDebtRatio(
            vault, new_strategy, int(5_001), sender=brain
        )

    target = int(8_000)
    max = target * 1.2
    increase = int(3_000)
    tx = debt_allocator.increaseStrategyDebtRatio(
        vault, strategy, increase, sender=brain
    )

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio(vault) == target
    assert debt_allocator.getStrategyConfig(vault, strategy) == (
        True,
        target,
        max,
        0,
        0,
    )

    target = int(10_000)
    max = int(10_000)
    increase = int(2_000)
    tx = debt_allocator.increaseStrategyDebtRatio(
        vault, strategy, increase, sender=brain
    )

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio(vault) == target
    assert debt_allocator.getStrategyConfig(vault, strategy) == (
        True,
        target,
        max,
        0,
        0,
    )


def test_decrease_debt_ratio(
    debt_allocator, brain, vault, strategy, daddy, create_strategy, user
):
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)

    minimum = int(1e17)
    target = int(5_000)
    max = target * 1.2

    vault.add_strategy(strategy.address, sender=daddy)
    debt_allocator.setMinimumChange(vault, minimum, sender=brain)

    # Underflow
    with ape.reverts():
        debt_allocator.decreaseStrategyDebtRatio(vault, strategy, target, sender=brain)

    # Add the target
    tx = debt_allocator.increaseStrategyDebtRatio(vault, strategy, target, sender=brain)

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio(vault) == target
    assert debt_allocator.getStrategyConfig(vault, strategy) == (
        True,
        target,
        max,
        0,
        0,
    )

    target = int(2_000)
    max = target * 1.2
    decrease = int(3_000)

    with ape.reverts("!manager"):
        debt_allocator.decreaseStrategyDebtRatio(vault, strategy, decrease, sender=user)

    tx = debt_allocator.decreaseStrategyDebtRatio(
        vault, strategy, decrease, sender=brain
    )

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio(vault) == target
    assert debt_allocator.getStrategyConfig(vault, strategy) == (
        True,
        target,
        max,
        0,
        0,
    )

    target = int(0)
    max = int(0)
    decrease = int(2_000)
    tx = debt_allocator.decreaseStrategyDebtRatio(
        vault, strategy, decrease, sender=brain
    )

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio(vault) == target
    assert debt_allocator.getStrategyConfig(vault, strategy) == (True, 0, 0, 0, 0)


def test_remove_strategy(
    debt_allocator, brain, vault, strategy, daddy, user, deposit_into_vault, amount
):
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)

    minimum = int(1)
    max = int(6_000)
    target = int(5_000)

    vault.add_strategy(strategy.address, sender=daddy)

    debt_allocator.setMinimumChange(vault, minimum, sender=brain)

    tx = debt_allocator.setStrategyDebtRatio(vault, strategy, target, max, sender=brain)

    event = list(tx.decode_logs(debt_allocator.StrategyChanged))[0]

    assert event.strategy == strategy
    assert event.status == 1

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio(vault) == target
    assert debt_allocator.getStrategyConfig(vault, strategy) == (
        True,
        target,
        max,
        0,
        0,
    )

    deposit_into_vault(vault, amount)
    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    print(debt_allocator.shouldUpdateDebt(vault, strategy))
    assert debt_allocator.shouldUpdateDebt(vault, strategy)[0] == True

    with ape.reverts("!manager"):
        debt_allocator.removeStrategy(vault, strategy, sender=user)

    tx = debt_allocator.removeStrategy(vault, strategy, sender=brain)

    event = list(tx.decode_logs(debt_allocator.StrategyChanged))

    assert len(event) == 1
    assert event[0].strategy == strategy
    assert event[0].status == 2
    assert debt_allocator.totalDebtRatio(vault) == 0
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)
    assert debt_allocator.shouldUpdateDebt(vault, strategy)[0] == False


def test_should_update_debt(
    debt_allocator, vault, strategy, brain, daddy, deposit_into_vault, amount
):
    assert debt_allocator.getStrategyConfig(vault, strategy.address) == (
        False,
        0,
        0,
        0,
        0,
    )
    vault.add_role(debt_allocator, ROLES.DEBT_MANAGER, sender=daddy)

    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == False
    assert bytes == ("!added").encode("utf-8")

    vault.add_strategy(strategy.address, sender=daddy)

    minimum = int(1)
    target = int(5_000)
    max = int(5_000)

    debt_allocator.setMinimumChange(vault, minimum, sender=brain)
    debt_allocator.setStrategyDebtRatio(vault, strategy, target, max, sender=brain)

    # Vault has no assets so should be false.
    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    deposit_into_vault(vault, amount)

    # No max debt has been set so should be false.
    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    # Should now want to allocate 50%
    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == True
    assert bytes == debt_allocator.update_debt.encode_input(
        vault, strategy.address, amount // 2
    )

    assert debt_allocator.isPaused(vault) == False
    debt_allocator.setPaused(vault, True, sender=brain)
    assert debt_allocator.isPaused(vault)

    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == False
    assert bytes == ("Paused").encode("utf-8")

    debt_allocator.setPaused(vault, False, sender=brain)
    assert debt_allocator.isPaused(vault) == False

    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == True
    assert bytes == debt_allocator.update_debt.encode_input(
        vault, strategy.address, amount // 2
    )

    debt_allocator.update_debt(vault, strategy, amount // 2, sender=brain)
    chain.mine(1)

    # Should now be false again once allocated
    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Update the ratio to make true
    debt_allocator.setStrategyDebtRatio(
        vault, strategy, int(target + 1), int(target + 1), sender=brain
    )

    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == True
    assert bytes == debt_allocator.update_debt.encode_input(
        vault, strategy.address, int(amount * 5_001 // 10_000)
    )

    # Set a minimumWait time
    debt_allocator.setMinimumWait(vault, MAX_INT, sender=brain)
    # Should now be false
    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == False
    assert bytes == ("min wait").encode("utf-8")

    debt_allocator.setMinimumWait(0, sender=brain)

    # Lower the max debt so its == to current debt
    vault.update_max_debt_for_strategy(strategy, int(amount // 2), sender=daddy)

    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Reset it.
    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == True
    assert bytes == debt_allocator.update_debt.encode_input(
        vault, strategy.address, int(amount * 5_001 // 10_000)
    )

    # Increase the minimum_total_idle
    vault.set_minimum_total_idle(vault.totalIdle(), sender=daddy)

    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == False
    assert bytes == ("No Idle").encode("utf-8")

    vault.set_minimum_total_idle(0, sender=daddy)

    # increase the minimum so its false again
    debt_allocator.setMinimumChange(vault, int(1e30), sender=brain)

    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Lower the target and minimum
    debt_allocator.setMinimumChange(vault, int(1), sender=brain)
    debt_allocator.setStrategyDebtRatio(
        vault, strategy, int(target // 2), int(target // 2), sender=brain
    )

    (bool, bytes) = debt_allocator.shouldUpdateDebt(vault, strategy.address)
    assert bool == True
    assert bytes == debt_allocator.update_debt.encode_input(
        vault, strategy.address, amount // 4
    )


def test_update_debt(
    debt_allocator,
    vault,
    strategy,
    brain,
    daddy,
    user,
    deposit_into_vault,
    amount,
):
    assert debt_allocator.getStrategyConfig(vault, strategy) == (False, 0, 0, 0, 0)
    deposit_into_vault(vault, amount)

    assert vault.totalIdle() == amount
    assert vault.totalDebt() == 0

    vault.add_strategy(strategy, sender=daddy)
    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    # This reverts by the allocator
    with ape.reverts("!keeper"):
        debt_allocator.update_debt(vault, strategy, amount, sender=user)

    # This reverts by the vault
    with ape.reverts("not allowed"):
        debt_allocator.update_debt(vault, strategy, amount, sender=brain)

    vault.add_role(
        debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )

    debt_allocator.update_debt(vault, strategy, amount, sender=brain)

    timestamp = debt_allocator.getStrategyConfig(vault, strategy)[3]
    assert timestamp != 0
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount

    debt_allocator.setKeeper(user, True, sender=brain)

    debt_allocator.update_debt(vault, strategy, 0, sender=user)

    assert debt_allocator.getStrategyConfig(vault, strategy)[2] != timestamp
    assert vault.totalIdle() == amount
    assert vault.totalDebt() == 0
