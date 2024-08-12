import ape
from ape import chain, project
from utils.constants import ZERO_ADDRESS, MAX_INT, ROLES


def test_setup(generic_allocator_factory, brain, user, strategy, vault):
    tx = generic_allocator_factory.newGenericDebtAllocator(vault, brain, 0, sender=user)

    events = list(tx.decode_logs(generic_allocator_factory.NewDebtAllocator))

    assert len(events) == 1
    assert events[0].vault == vault.address

    generic_allocator = project.GenericDebtAllocator.at(events[0].allocator)

    assert generic_allocator.maxAcceptableBaseFee() == MAX_INT
    assert generic_allocator.keepers(brain) == True
    assert generic_allocator.managers(brain) == False
    assert generic_allocator.vault() == vault.address
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)
    assert generic_allocator.totalDebtRatio() == 0
    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("!added").encode("utf-8")


def test_set_keepers(generic_allocator, brain, user):
    assert generic_allocator.keepers(brain) == True
    assert generic_allocator.keepers(user) == False

    with ape.reverts("!governance"):
        generic_allocator.setKeeper(user, True, sender=user)

    tx = generic_allocator.setKeeper(user, True, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateKeeper))[0]

    assert event.keeper == user
    assert event.allowed == True
    assert generic_allocator.keepers(user) == True

    tx = generic_allocator.setKeeper(brain, False, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateKeeper))[0]

    assert event.keeper == brain
    assert event.allowed == False
    assert generic_allocator.keepers(brain) == False


def test_set_managers(generic_allocator, brain, user):
    assert generic_allocator.managers(brain) == False
    assert generic_allocator.managers(user) == False

    with ape.reverts("!governance"):
        generic_allocator.setManager(user, True, sender=user)

    tx = generic_allocator.setManager(user, True, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateManager))[0]

    assert event.manager == user
    assert event.allowed == True
    assert generic_allocator.managers(user) == True

    tx = generic_allocator.setManager(user, False, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateManager))[0]

    assert event.manager == user
    assert event.allowed == False
    assert generic_allocator.managers(user) == False


def test_set_minimum_change(generic_allocator, brain, strategy, user):
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)
    assert generic_allocator.minimumChange() != 0

    minimum = int(1e17)

    with ape.reverts("!governance"):
        generic_allocator.setMinimumChange(minimum, sender=user)

    with ape.reverts("zero"):
        generic_allocator.setMinimumChange(0, sender=brain)

    tx = generic_allocator.setMinimumChange(minimum, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateMinimumChange))[0]

    assert event.newMinimumChange == minimum
    assert generic_allocator.minimumChange() == minimum


def test_set_minimum_wait(generic_allocator, brain, strategy, user):
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)
    assert generic_allocator.minimumWait() == 0

    minimum = int(1e17)

    with ape.reverts("!governance"):
        generic_allocator.setMinimumWait(minimum, sender=user)

    tx = generic_allocator.setMinimumWait(minimum, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateMinimumWait))[0]

    assert event.newMinimumWait == minimum
    assert generic_allocator.minimumWait() == minimum


def test_set_max_debt_update_loss(generic_allocator, brain, strategy, user):
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)
    assert generic_allocator.maxDebtUpdateLoss() == 1

    max = int(69)

    with ape.reverts("!governance"):
        generic_allocator.setMaxDebtUpdateLoss(max, sender=user)

    with ape.reverts("higher than max"):
        generic_allocator.setMaxDebtUpdateLoss(10_001, sender=brain)

    tx = generic_allocator.setMaxDebtUpdateLoss(max, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateMaxDebtUpdateLoss))[0]

    assert event.newMaxDebtUpdateLoss == max
    assert generic_allocator.maxDebtUpdateLoss() == max


def test_set_ratios(
    generic_allocator, brain, daddy, vault, strategy, create_strategy, user
):
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)

    minimum = int(1e17)
    max = int(6_000)
    target = int(5_000)

    with ape.reverts("!manager"):
        generic_allocator.setStrategyDebtRatio(strategy, target, max, sender=user)

    vault.add_strategy(strategy.address, sender=daddy)

    with ape.reverts("max too high"):
        generic_allocator.setStrategyDebtRatio(
            strategy, target, int(10_001), sender=brain
        )

    with ape.reverts("max ratio"):
        generic_allocator.setStrategyDebtRatio(
            strategy, int(max + 1), max, sender=brain
        )

    tx = generic_allocator.setStrategyDebtRatio(strategy, target, max, sender=brain)

    event = list(tx.decode_logs(generic_allocator.StrategyChanged))[0]

    assert event.strategy == strategy
    assert event.status == 1

    event = list(tx.decode_logs(generic_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_allocator.totalDebtRatio() == target
    assert generic_allocator.getConfig(strategy) == (True, target, max, 0, 0)

    new_strategy = create_strategy()
    vault.add_strategy(new_strategy, sender=daddy)
    with ape.reverts("ratio too high"):
        generic_allocator.setStrategyDebtRatio(
            new_strategy, int(10_000), int(10_000), sender=brain
        )

    target = int(8_000)
    tx = generic_allocator.setStrategyDebtRatio(strategy, target, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == target * 1.2
    assert event.newTotalDebtRatio == target
    assert generic_allocator.totalDebtRatio() == target
    assert generic_allocator.getConfig(strategy) == (True, target, target * 1.2, 0, 0)


def test_increase_debt_ratio(
    generic_allocator, brain, daddy, vault, strategy, create_strategy, user
):
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)

    minimum = int(1e17)
    target = int(5_000)
    increase = int(5_000)
    max = target * 1.2

    with ape.reverts("!manager"):
        generic_allocator.increaseStrategyDebtRatio(strategy, increase, sender=user)

    vault.add_strategy(strategy.address, sender=daddy)

    tx = generic_allocator.increaseStrategyDebtRatio(strategy, increase, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_allocator.totalDebtRatio() == target
    assert generic_allocator.getConfig(strategy) == (True, target, max, 0, 0)

    new_strategy = create_strategy()
    vault.add_strategy(new_strategy, sender=daddy)

    with ape.reverts("ratio too high"):
        generic_allocator.increaseStrategyDebtRatio(
            new_strategy, int(5_001), sender=brain
        )

    target = int(8_000)
    max = target * 1.2
    increase = int(3_000)
    tx = generic_allocator.increaseStrategyDebtRatio(strategy, increase, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_allocator.totalDebtRatio() == target
    assert generic_allocator.getConfig(strategy) == (True, target, max, 0, 0)

    target = int(10_000)
    max = int(10_000)
    increase = int(2_000)
    tx = generic_allocator.increaseStrategyDebtRatio(strategy, increase, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_allocator.totalDebtRatio() == target
    assert generic_allocator.getConfig(strategy) == (True, target, max, 0, 0)


def test_decrease_debt_ratio(
    generic_allocator, brain, vault, strategy, daddy, create_strategy, user
):
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)

    minimum = int(1e17)
    target = int(5_000)
    max = target * 1.2

    vault.add_strategy(strategy.address, sender=daddy)
    generic_allocator.setMinimumChange(minimum, sender=brain)

    # Underflow
    with ape.reverts():
        generic_allocator.decreaseStrategyDebtRatio(strategy, target, sender=brain)

    # Add the target
    tx = generic_allocator.increaseStrategyDebtRatio(strategy, target, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_allocator.totalDebtRatio() == target
    assert generic_allocator.getConfig(strategy) == (True, target, max, 0, 0)

    target = int(2_000)
    max = target * 1.2
    decrease = int(3_000)

    with ape.reverts("!manager"):
        generic_allocator.decreaseStrategyDebtRatio(strategy, decrease, sender=user)

    tx = generic_allocator.decreaseStrategyDebtRatio(strategy, decrease, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_allocator.totalDebtRatio() == target
    assert generic_allocator.getConfig(strategy) == (True, target, max, 0, 0)

    target = int(0)
    max = int(0)
    decrease = int(2_000)
    tx = generic_allocator.decreaseStrategyDebtRatio(strategy, decrease, sender=brain)

    event = list(tx.decode_logs(generic_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_allocator.totalDebtRatio() == target
    assert generic_allocator.getConfig(strategy) == (True, 0, 0, 0, 0)


def test_remove_strategy(
    generic_allocator, brain, vault, strategy, daddy, user, deposit_into_vault, amount
):
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)

    minimum = int(1)
    max = int(6_000)
    target = int(5_000)

    vault.add_strategy(strategy.address, sender=daddy)

    generic_allocator.setMinimumChange(minimum, sender=brain)

    tx = generic_allocator.setStrategyDebtRatio(strategy, target, max, sender=brain)

    event = list(tx.decode_logs(generic_allocator.StrategyChanged))[0]

    assert event.strategy == strategy
    assert event.status == 1

    event = list(tx.decode_logs(generic_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert generic_allocator.totalDebtRatio() == target
    assert generic_allocator.getConfig(strategy) == (True, target, max, 0, 0)

    deposit_into_vault(vault, amount)
    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    print(generic_allocator.shouldUpdateDebt(strategy))
    assert generic_allocator.shouldUpdateDebt(strategy)[0] == True

    with ape.reverts("!manager"):
        generic_allocator.removeStrategy(strategy, sender=user)

    tx = generic_allocator.removeStrategy(strategy, sender=brain)

    event = list(tx.decode_logs(generic_allocator.StrategyChanged))

    assert len(event) == 1
    assert event[0].strategy == strategy
    assert event[0].status == 2
    assert generic_allocator.totalDebtRatio() == 0
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)
    assert generic_allocator.shouldUpdateDebt(strategy)[0] == False


def test_should_update_debt(
    generic_allocator, vault, strategy, brain, daddy, deposit_into_vault, amount
):
    assert generic_allocator.getConfig(strategy.address) == (False, 0, 0, 0, 0)
    vault.add_role(generic_allocator, ROLES.DEBT_MANAGER, sender=daddy)

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("!added").encode("utf-8")

    vault.add_strategy(strategy.address, sender=daddy)

    minimum = int(1)
    target = int(5_000)
    max = int(5_000)

    generic_allocator.setMinimumChange(minimum, sender=brain)
    generic_allocator.setStrategyDebtRatio(strategy, target, max, sender=brain)

    # Vault has no assets so should be false.
    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    deposit_into_vault(vault, amount)

    # No max debt has been set so should be false.
    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    # Should now want to allocate 50%
    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    print("got", bytes)
    print("Made ", vault.update_debt.encode_input(strategy.address, amount // 2))
    assert bytes == vault.update_debt.encode_input(strategy.address, amount // 2)

    generic_allocator.update_debt(strategy, amount // 2, sender=brain)
    chain.mine(1)

    # Should now be false again once allocated
    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Update the ratio to make true
    generic_allocator.setStrategyDebtRatio(
        strategy, int(target + 1), int(target + 1), sender=brain
    )

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(
        strategy.address, int(amount * 5_001 // 10_000)
    )

    # Set a minimumWait time
    generic_allocator.setMinimumWait(MAX_INT, sender=brain)
    # Should now be false
    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("min wait").encode("utf-8")

    generic_allocator.setMinimumWait(0, sender=brain)

    # Lower the max debt so its == to current debt
    vault.update_max_debt_for_strategy(strategy, int(amount // 2), sender=daddy)

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Reset it.
    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(
        strategy.address, int(amount * 5_001 // 10_000)
    )

    # Increase the minimum_total_idle
    vault.set_minimum_total_idle(vault.totalIdle(), sender=daddy)

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("No Idle").encode("utf-8")

    vault.set_minimum_total_idle(0, sender=daddy)

    # increase the minimum so its false again
    generic_allocator.setMinimumChange(int(1e30), sender=brain)

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("Below Min").encode("utf-8")

    # Lower the target and minimum
    generic_allocator.setMinimumChange(int(1), sender=brain)
    generic_allocator.setStrategyDebtRatio(
        strategy, int(target // 2), int(target // 2), sender=brain
    )

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy.address, amount // 4)


def test_update_debt(
    generic_allocator,
    vault,
    strategy,
    brain,
    daddy,
    user,
    deposit_into_vault,
    amount,
):
    assert generic_allocator.getConfig(strategy) == (False, 0, 0, 0, 0)
    deposit_into_vault(vault, amount)

    assert vault.totalIdle() == amount
    assert vault.totalDebt() == 0

    vault.add_strategy(strategy, sender=daddy)
    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    # This reverts by the allocator
    with ape.reverts("!keeper"):
        generic_allocator.update_debt(strategy, amount, sender=user)

    # This reverts by the vault
    with ape.reverts("not allowed"):
        generic_allocator.update_debt(strategy, amount, sender=brain)

    vault.add_role(
        generic_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )

    generic_allocator.update_debt(strategy, amount, sender=brain)

    timestamp = generic_allocator.getConfig(strategy)[3]
    assert timestamp != 0
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount

    generic_allocator.setKeeper(user, True, sender=brain)

    generic_allocator.update_debt(strategy, 0, sender=user)

    assert generic_allocator.getConfig(strategy)[2] != timestamp
    assert vault.totalIdle() == amount
    assert vault.totalDebt() == 0


def test_pause(
    generic_allocator, vault, strategy, brain, daddy, user, deposit_into_vault, amount
):
    assert generic_allocator.paused() == False
    assert generic_allocator.getConfig(strategy.address) == (False, 0, 0, 0, 0)
    vault.add_role(generic_allocator, ROLES.DEBT_MANAGER, sender=daddy)

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("!added").encode("utf-8")

    vault.add_strategy(strategy.address, sender=daddy)

    minimum = int(1)
    target = int(5_000)
    max = int(5_000)

    generic_allocator.setMinimumChange(minimum, sender=brain)
    generic_allocator.setStrategyDebtRatio(strategy, target, max, sender=brain)
    deposit_into_vault(vault, amount)
    vault.update_max_debt_for_strategy(strategy, MAX_INT, sender=daddy)

    # Should now want to allocate 50%
    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy.address, amount // 2)

    # Pause the allocator

    # with ape.reverts("!governance"):
    #   generic_allocator.setPaused(True, sender=user)

    tx = generic_allocator.setPaused(True, sender=brain)

    assert generic_allocator.paused() == True

    events = list(tx.decode_logs(generic_allocator.UpdatePaused))

    assert len(events) == 1
    assert events[0].status == True

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == False
    assert bytes == ("paused").encode("utf-8")

    # Unpause
    tx = generic_allocator.setPaused(False, sender=brain)

    assert generic_allocator.paused() == False
    events = list(tx.decode_logs(generic_allocator.UpdatePaused))

    assert len(events) == 1
    assert events[0].status == False

    (bool, bytes) = generic_allocator.shouldUpdateDebt(strategy.address)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy.address, amount // 2)
