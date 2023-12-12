import ape
from ape import chain, project, networks
from utils.constants import ZERO_ADDRESS, MAX_INT, ROLES


def setup_vault(vault, strategies, oracle, chad):
    for strategy in strategies:
        vault.add_strategy(strategy, sender=chad)
        vault.update_max_debt_for_strategy(strategy, 2**256 - 1, sender=chad)
        management = strategy.management()
        oracle.setOracle(strategy, strategy, sender=management)


def test_yield_manager_setup(yield_manager, daddy, management, strategy_manager):
    assert yield_manager.strategyManager() == strategy_manager
    assert yield_manager.governance() == daddy
    assert yield_manager.open() == False
    assert yield_manager.maxDebtUpdateLoss() == 1
    assert yield_manager.allocators(management) == False


def test_setters(yield_manager, daddy, management):
    assert yield_manager.allocators(management) == False
    assert yield_manager.open() == False
    assert yield_manager.maxDebtUpdateLoss() == 1

    with ape.reverts("!governance"):
        yield_manager.setAllocator(management, True, sender=management)

    tx = yield_manager.setAllocator(management, True, sender=daddy)

    event = list(tx.decode_logs(yield_manager.UpdateAllocator))[0]

    assert event.allocator == management
    assert event.status == True
    assert yield_manager.allocators(management) == True

    tx = yield_manager.setAllocator(management, False, sender=daddy)

    event = list(tx.decode_logs(yield_manager.UpdateAllocator))[0]

    assert event.allocator == management
    assert event.status == False
    assert yield_manager.allocators(management) == False

    loss = int(8)
    with ape.reverts("!governance"):
        yield_manager.setMaxDebtUpdateLoss(loss, sender=management)

    tx = yield_manager.setMaxDebtUpdateLoss(loss, sender=daddy)

    event = list(tx.decode_logs(yield_manager.UpdateMaxDebtUpdateLoss))[0]

    assert event.newMaxDebtUpdateLoss == loss
    assert yield_manager.maxDebtUpdateLoss() == loss

    with ape.reverts("!governance"):
        yield_manager.setOpen(True, sender=management)

    tx = yield_manager.setOpen(True, sender=daddy)

    event = list(tx.decode_logs(yield_manager.UpdateOpen))[0]

    assert event.status == True
    assert yield_manager.open()


def test_update_allocation(
    apr_oracle,
    yield_manager,
    vault,
    management,
    strategy_manager,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    # Can just pass in one at to allocate
    allocation = [(strategy_two, amount)]

    with ape.reverts("!allocator or open"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    yield_manager.setAllocator(user, True, sender=daddy)

    # Must give allocator the debt role
    with ape.reverts("not allowed"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    vault.set_role(
        yield_manager, ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER, sender=daddy
    )

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    (before, now) = tx.return_value

    assert before == 0
    # assert now == int(1e17 * amount)
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_two).current_debt == amount

    allocation = []
    with ape.reverts("cheater"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    allocation = [(strategy_one, amount)]
    with ape.reverts("no funds to deposit"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    allocation = [(strategy_two, amount // 2)]
    with ape.reverts("fail"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    # strategy one is now earning more
    strategy_one.setApr(int(1.5e17), sender=management)

    # only move part
    to_move = amount // 2
    # will revert if in the wrong order
    allocation = [(strategy_one, to_move), (strategy_two, amount - to_move)]
    with ape.reverts("no funds to deposit"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    allocation = [(strategy_two, amount - to_move), (strategy_one, to_move)]
    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(vault.DebtUpdated))) == 2
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount
    assert vault.totalAssets() == amount
    assert vault.strategies(strategy_one).current_debt == to_move
    assert vault.strategies(strategy_two).current_debt == amount - to_move

    # Try and move all
    allocation = [(strategy_two, 0), (strategy_one, amount)]
    # Strategy manager isnt the strategies management
    with ape.reverts("!debt manager"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    strategy_two.setPendingManagement(strategy_manager, sender=management)
    strategy_two.setProfitMaxUnlockTime(int(200), sender=management)
    strategy_manager.manageNewStrategy(strategy_two, yield_manager, sender=management)

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(vault.DebtUpdated))) == 2
    assert len(list(tx.decode_logs(strategy_two.UpdateProfitMaxUnlockTime))) == 2
    assert len(list(tx.decode_logs(strategy_two.Reported))) == 1
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount
    assert vault.totalAssets() == amount
    assert vault.strategies(strategy_one).current_debt == amount
    assert vault.strategies(strategy_two).current_debt == 0

    # Try and move all them all back
    allocation = [(strategy_one, 1), (strategy_two, amount)]
    with ape.reverts("fail"):
        yield_manager.updateAllocation(vault, allocation, sender=user)


def test_update_allocation_pending_profit(
    apr_oracle,
    yield_manager,
    vault,
    management,
    strategy_manager,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    vault.add_role(
        yield_manager, ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER, sender=daddy
    )
    strategy_one.setPendingManagement(strategy_manager, sender=management)
    strategy_one.setProfitMaxUnlockTime(int(200), sender=management)
    strategy_manager.manageNewStrategy(strategy_one, yield_manager, sender=management)
    yield_manager.setAllocator(user, True, sender=daddy)

    profit = amount // 10
    amount = amount - profit

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    vault.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    asset.transfer(strategy_one, profit, sender=user)

    allocation = [(strategy_one, 0), (strategy_two, amount + profit)]

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(vault.DebtUpdated))) == 2
    assert len(list(tx.decode_logs(vault.StrategyReported))) == 1
    assert len(list(tx.decode_logs(strategy_one.Reported))) == 1
    assert len(list(tx.decode_logs(strategy_two.UpdateProfitMaxUnlockTime))) == 2
    assert vault.totalAssets() == amount + profit
    assert vault.totalDebt() == amount + profit
    assert vault.strategies(strategy_one).current_debt == 0
    assert vault.strategies(strategy_two).current_debt == amount + profit
    assert strategy_one.balanceOf(vault) == 0


def test_update_allocation_pending_loss(
    apr_oracle,
    yield_manager,
    vault,
    management,
    strategy_manager,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    vault.add_role(
        yield_manager, ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER, sender=daddy
    )
    strategy_one.setPendingManagement(strategy_manager, sender=management)
    strategy_one.setProfitMaxUnlockTime(int(200), sender=management)
    strategy_manager.manageNewStrategy(strategy_one, yield_manager, sender=management)
    yield_manager.setAllocator(user, True, sender=daddy)

    loss = amount // 10

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    vault.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    asset.transfer(user, loss, sender=strategy_one)

    allocation = [(strategy_one, 0), (strategy_two, amount)]

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(vault.DebtUpdated))) == 2
    assert len(list(tx.decode_logs(vault.StrategyReported))) == 1
    assert vault.totalAssets() == amount - loss
    assert vault.totalDebt() == amount - loss
    assert vault.strategies(strategy_one).current_debt == 0
    assert vault.strategies(strategy_two).current_debt == amount - loss
    assert strategy_one.balanceOf(vault) == 0


def test_update_allocation_pending_loss_move_half(
    apr_oracle,
    yield_manager,
    vault,
    management,
    strategy_manager,
    daddy,
    user,
    keeper,
    amount,
    asset,
    deploy_mock_tokenized,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    vault.add_role(
        yield_manager, ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER, sender=daddy
    )
    strategy_one.setPendingManagement(strategy_manager, sender=management)
    strategy_one.setProfitMaxUnlockTime(int(200), sender=management)
    strategy_manager.manageNewStrategy(strategy_one, yield_manager, sender=management)
    yield_manager.setAllocator(user, True, sender=daddy)

    loss = amount // 10

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    vault.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    # Record strategy loss
    asset.transfer(user, loss, sender=strategy_one)
    strategy_one.report(sender=keeper)

    to_move = amount // 2
    allocation = [(strategy_one, amount - to_move), (strategy_two, amount)]

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(vault.DebtUpdated))) == 2
    assert len(list(tx.decode_logs(vault.StrategyReported))) == 1
    assert vault.totalAssets() == amount - loss
    assert vault.totalDebt() == amount - loss
    assert vault.strategies(strategy_one).current_debt == amount - to_move
    assert vault.strategies(strategy_two).current_debt == to_move - loss
    assert strategy_one.balanceOf(vault) != 0


def test_update_allocation_loss_on_withdraw(
    apr_oracle,
    yield_manager,
    vault,
    management,
    strategy_manager,
    daddy,
    user,
    keeper,
    amount,
    asset,
    deploy_mock_tokenized,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    vault.add_role(
        yield_manager, ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER, sender=daddy
    )
    strategy_one.setPendingManagement(strategy_manager, sender=management)
    strategy_one.setProfitMaxUnlockTime(int(200), sender=management)
    strategy_manager.manageNewStrategy(strategy_one, yield_manager, sender=management)
    yield_manager.setAllocator(user, True, sender=daddy)

    loss = amount // 10

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    vault.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    # simulate strategy loss
    strategy_one.realizeLoss(loss, sender=daddy)

    allocation = [(strategy_one, 1), (strategy_two, amount)]

    with ape.reverts("too much loss"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    yield_manager.setMaxDebtUpdateLoss(1_000, sender=daddy)

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(vault.DebtUpdated))) == 2
    assert len(list(tx.decode_logs(vault.StrategyReported))) == 0
    assert vault.totalAssets() == amount - loss + 1
    assert vault.totalDebt() == amount - loss + 1
    assert vault.strategies(strategy_one).current_debt == 1
    assert vault.strategies(strategy_two).current_debt == amount - loss


def test_validate_allocation(
    apr_oracle, yield_manager, vault, daddy, user, amount, asset, deploy_mock_tokenized
):
    strategy_one = deploy_mock_tokenized("One")
    strategy_two = deploy_mock_tokenized("two")
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    # Can validate the allocation with no strategies when all is idle
    assert vault.totalIdle() == amount

    assert yield_manager.validateAllocation(vault, [])
    assert yield_manager.validateAllocation(vault, [(strategy_one, amount)])
    assert yield_manager.validateAllocation(
        vault, [(strategy_one, amount), (strategy_two, 0)]
    )

    vault.update_debt(strategy_one, amount // 2, sender=daddy)

    assert yield_manager.validateAllocation(vault, []) == False
    assert yield_manager.validateAllocation(vault, [(strategy_one, amount)])
    assert yield_manager.validateAllocation(
        vault, [(strategy_one, amount), (strategy_two, 0)]
    )

    # Now will be false
    vault.update_debt(strategy_two, vault.totalIdle() // 2, sender=daddy)

    assert yield_manager.validateAllocation(vault, []) == False
    assert yield_manager.validateAllocation(vault, [(strategy_one, amount)]) == False
    assert yield_manager.validateAllocation(
        vault, [(strategy_one, amount), (strategy_two, 0)]
    )


def test_get_current_and_expected(
    apr_oracle,
    yield_manager,
    vault,
    management,
    strategy_manager,
    daddy,
    user,
    keeper,
    amount,
    asset,
    deploy_mock_tokenized,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    allocation = []
    (current, expected) = yield_manager.getCurrentAndExpectedYield(vault, allocation)

    assert current == 0
    assert expected == 0

    allocation = [(strategy_one, 0), (strategy_two, 0)]
    (current, expected) = yield_manager.getCurrentAndExpectedYield(vault, allocation)
    assert current == 0
    assert expected == 0

    allocation = [(strategy_one, amount), (strategy_two, 0)]
    (current, expected) = yield_manager.getCurrentAndExpectedYield(vault, allocation)
    assert current == 0
    assert expected != 0

    vault.update_debt(strategy_one, amount, sender=daddy)

    allocation = [(strategy_one, 0), (strategy_two, amount)]
    (current, new_expected) = yield_manager.getCurrentAndExpectedYield(
        vault, allocation
    )
    assert current == expected
    assert expected != 0
    assert expected > 0

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount


def test_update_allocation_permissioned(
    apr_oracle,
    yield_manager,
    vault,
    management,
    strategy_manager,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    vault.set_role(
        yield_manager, ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER, sender=daddy
    )

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    # Can just pass in one at to allocate
    allocation = [(strategy_two, amount)]

    with ape.reverts("!governance"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=user)

    yield_manager.setAllocator(user, True, sender=daddy)

    # Still cant allocate even with allocator role
    with ape.reverts("!governance"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=user)

    tx = yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    # assert now == int(1e17 * amount)
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_two).current_debt == amount

    allocation = [(strategy_one, amount)]
    with ape.reverts("no funds to deposit"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    # strategy one is now earning more
    strategy_one.setApr(int(1.5e17), sender=management)

    # only move part
    to_move = amount // 2
    # will revert if in the wrong order
    allocation = [(strategy_one, to_move), (strategy_two, amount - to_move)]
    with ape.reverts("no funds to deposit"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    allocation = [(strategy_two, amount - to_move), (strategy_one, to_move)]
    tx = yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    assert len(list(tx.decode_logs(vault.DebtUpdated))) == 2
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount
    assert vault.totalAssets() == amount
    assert vault.strategies(strategy_one).current_debt == to_move
    assert vault.strategies(strategy_two).current_debt == amount - to_move

    # Try and move all
    allocation = [(strategy_two, 0), (strategy_one, amount)]
    # Strategy manager isnt the strategies management
    with ape.reverts("!debt manager"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    strategy_two.setPendingManagement(strategy_manager, sender=management)
    strategy_two.setProfitMaxUnlockTime(int(200), sender=management)
    strategy_manager.manageNewStrategy(strategy_two, yield_manager, sender=management)

    tx = yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    assert len(list(tx.decode_logs(vault.DebtUpdated))) == 2
    assert len(list(tx.decode_logs(strategy_two.UpdateProfitMaxUnlockTime))) == 2
    assert len(list(tx.decode_logs(strategy_two.Reported))) == 1
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount
    assert vault.totalAssets() == amount
    assert vault.strategies(strategy_one).current_debt == amount
    assert vault.strategies(strategy_two).current_debt == 0
