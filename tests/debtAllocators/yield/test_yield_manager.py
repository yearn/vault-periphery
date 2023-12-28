import ape
from ape import chain, project, networks
from utils.constants import ZERO_ADDRESS, MAX_INT, ROLES, MAX_BPS


def setup_vault(vault, strategies, oracle, chad):
    for strategy in strategies:
        vault.add_strategy(strategy, sender=chad)
        vault.update_max_debt_for_strategy(strategy, 2**256 - 1, sender=chad)
        management = strategy.management()
        strategy.setProfitMaxUnlockTime(1, sender=management)
        oracle.setOracle(strategy, strategy, sender=management)


def test_yield_manager_setup(yield_manager, daddy, vault, management, keeper):
    assert yield_manager.keeper() == keeper
    assert yield_manager.governance() == daddy
    assert yield_manager.open() == False
    assert yield_manager.proposer(management) == False
    assert yield_manager.vaultAllocator(vault) == ZERO_ADDRESS


def test_setters(yield_manager, daddy, vault, generic_debt_allocator, management):
    assert yield_manager.vaultAllocator(vault) == ZERO_ADDRESS
    assert yield_manager.proposer(management) == False
    assert yield_manager.open() == False

    with ape.reverts("!governance"):
        yield_manager.setVaultAllocator(
            vault, generic_debt_allocator, sender=management
        )

    tx = yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)

    event = list(tx.decode_logs(yield_manager.UpdateVaultAllocator))[0]

    assert event.vault == vault
    assert event.allocator == generic_debt_allocator
    assert yield_manager.vaultAllocator(vault) == generic_debt_allocator

    with ape.reverts("!governance"):
        yield_manager.setProposer(management, True, sender=management)

    tx = yield_manager.setProposer(management, True, sender=daddy)

    event = list(tx.decode_logs(yield_manager.UpdateProposer))[0]

    assert event.proposer == management
    assert event.status == True
    assert yield_manager.proposer(management) == True

    tx = yield_manager.setProposer(management, False, sender=daddy)

    event = list(tx.decode_logs(yield_manager.UpdateProposer))[0]

    assert event.proposer == management
    assert event.status == False
    assert yield_manager.proposer(management) == False

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
    keeper,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    keeper.setKeeper(yield_manager, True, sender=daddy)

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    # Can just pass in one at to allocate
    allocation = [(strategy_two, amount)]

    with ape.reverts("!allocator or open"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    yield_manager.setProposer(user, True, sender=daddy)

    with ape.reverts("vault not added"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)

    # Must give allocator the keeper role
    with ape.reverts("!keeper"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    generic_debt_allocator.setKeeper(yield_manager, True, sender=daddy)
    generic_debt_allocator.setMinimumChange(1, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    (before, now) = tx.return_value

    assert generic_debt_allocator.configs(strategy_two).targetRatio == MAX_BPS
    assert generic_debt_allocator.configs(strategy_one).targetRatio == 0
    assert generic_debt_allocator.shouldUpdateDebt(strategy_one)[0] == False
    assert generic_debt_allocator.shouldUpdateDebt(strategy_two)[0] == True
    assert generic_debt_allocator.shouldUpdateDebt(strategy_two)[
        1
    ] == vault.update_debt.encode_input(strategy_two.address, amount)
    assert before == 0

    generic_debt_allocator.update_debt(strategy_two, amount, sender=daddy)
    assert generic_debt_allocator.shouldUpdateDebt(strategy_two)[0] == False

    # assert now == int(1e17 * amount)
    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_two).current_debt == amount

    allocation = []
    with ape.reverts("cheater"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    allocation = [(strategy_one, amount)]
    with ape.reverts("ratio too high"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    print(
        f"Max redeem is {strategy_two.maxRedeem(vault)}, Max withdraw is {strategy_two.convertToAssets(strategy_two.maxRedeem(vault))}, amount is {amount}"
    )
    allocation = [(strategy_two, amount // 2)]
    with ape.reverts("fail"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    # strategy one is now earning more
    strategy_one.setApr(int(1.5e17), sender=management)

    # only move part
    to_move = amount // 2
    # will revert if in the wrong order
    allocation = [(strategy_one, to_move), (strategy_two, amount - to_move)]
    with ape.reverts("ratio too high"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    allocation = [(strategy_two, amount - to_move), (strategy_one, to_move)]
    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert generic_debt_allocator.configs(strategy_two).targetRatio != MAX_BPS
    assert generic_debt_allocator.configs(strategy_one).targetRatio != 0
    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    (bool_two, bytes_two) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool_one == False
    assert bool_two == True
    assert bytes_two == vault.update_debt.encode_input(
        strategy_two.address, amount - to_move
    )

    generic_debt_allocator.update_debt(strategy_two, amount - to_move, sender=daddy)

    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    assert bool_one == True
    assert bytes_one == vault.update_debt.encode_input(strategy_one, to_move)

    generic_debt_allocator.update_debt(strategy_one, to_move, sender=daddy)

    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    (bool_two, bytes_two) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool_one == False
    assert bool_two == False

    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount
    assert vault.totalAssets() == amount
    assert vault.strategies(strategy_one).current_debt == to_move
    assert vault.strategies(strategy_two).current_debt == amount - to_move

    # Try and move all
    allocation = [(strategy_two, 0), (strategy_one, amount)]
    # Strategy manager isnt the strategies management
    with ape.reverts("!keeper"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    strategy_two.setKeeper(keeper, sender=management)
    keeper.addNewStrategy(strategy_two, sender=daddy)

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert generic_debt_allocator.configs(strategy_two).targetRatio == 0
    assert generic_debt_allocator.configs(strategy_one).targetRatio == MAX_BPS
    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    (bool_two, bytes_two) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool_one == False
    assert bool_two == True
    assert bytes_two == vault.update_debt.encode_input(strategy_two.address, 0)

    generic_debt_allocator.update_debt(strategy_two, 0, sender=daddy)

    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    assert bool_one == True
    assert bytes_one == vault.update_debt.encode_input(strategy_one, amount)

    generic_debt_allocator.update_debt(strategy_one, amount, sender=daddy)

    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    (bool_two, bytes_two) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool_one == False
    assert bool_two == False

    # assert len(list(tx.decode_logs(strategy_two.Reported))) == 1
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
    keeper,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)
    generic_debt_allocator.setKeeper(yield_manager, True, sender=daddy)
    generic_debt_allocator.setMinimumChange(1, sender=daddy)
    vault.add_role(yield_manager, ROLES.REPORTING_MANAGER, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )
    strategy_one.setKeeper(keeper, sender=management)
    keeper.addNewStrategy(strategy_one, sender=daddy)
    keeper.setKeeper(yield_manager, True, sender=daddy)
    yield_manager.setProposer(user, True, sender=daddy)

    profit = amount // 10
    amount = amount - profit

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    generic_debt_allocator.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    asset.transfer(strategy_one, profit, sender=user)

    allocation = [(strategy_one, 0), (strategy_two, amount + profit)]

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(strategy_one.Reported))) == 1

    assert generic_debt_allocator.shouldUpdateDebt(strategy_two)[0] == False
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy_one, 0)

    tx = generic_debt_allocator.update_debt(strategy_one, 0, sender=daddy)

    event = list(tx.decode_logs(vault.StrategyReported))
    assert len(event) == 1
    assert event[0].gain == profit

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy_two, amount + profit)


def test_update_allocation_pending_loss(
    apr_oracle,
    yield_manager,
    vault,
    management,
    keeper,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)
    generic_debt_allocator.setKeeper(yield_manager, True, sender=daddy)
    generic_debt_allocator.setMinimumChange(1, sender=daddy)
    vault.add_role(yield_manager, ROLES.REPORTING_MANAGER, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )
    strategy_one.setKeeper(keeper, sender=management)
    keeper.addNewStrategy(strategy_one, sender=daddy)
    keeper.setKeeper(yield_manager, True, sender=daddy)
    yield_manager.setProposer(user, True, sender=daddy)

    loss = amount // 10

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    generic_debt_allocator.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    asset.transfer(user, loss, sender=strategy_one)

    allocation = [(strategy_one, 0), (strategy_two, amount)]

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(vault.StrategyReported))) == 1

    assert generic_debt_allocator.shouldUpdateDebt(strategy_two)[0] == False
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy_one, 0)

    generic_debt_allocator.update_debt(strategy_one, 0, sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy_two, amount - loss)


def test_update_allocation_pending_loss_move_half(
    apr_oracle,
    yield_manager,
    vault,
    management,
    keeper,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)
    generic_debt_allocator.setKeeper(yield_manager, True, sender=daddy)
    generic_debt_allocator.setMinimumChange(1, sender=daddy)
    vault.add_role(yield_manager, ROLES.REPORTING_MANAGER, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )
    strategy_one.setKeeper(keeper, sender=management)
    keeper.addNewStrategy(strategy_one, sender=daddy)
    keeper.setKeeper(yield_manager, True, sender=daddy)
    yield_manager.setProposer(user, True, sender=daddy)

    loss = amount // 10

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    generic_debt_allocator.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    # Record strategy loss
    asset.transfer(user, loss, sender=strategy_one)
    strategy_one.report(sender=keeper)

    to_move = amount // 2
    allocation = [(strategy_one, amount - loss - to_move), (strategy_two, to_move)]

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(vault.StrategyReported))) == 1
    assert vault.totalAssets() < amount

    assert generic_debt_allocator.shouldUpdateDebt(strategy_two)[0] == False
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    assert bool == True

    generic_debt_allocator.update_debt(strategy_one, amount - to_move, sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy_two, to_move - loss)


def test_update_allocation_pending_loss_move_all(
    apr_oracle,
    yield_manager,
    vault,
    management,
    keeper,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)
    generic_debt_allocator.setKeeper(yield_manager, True, sender=daddy)
    generic_debt_allocator.setMinimumChange(1, sender=daddy)
    vault.add_role(yield_manager, ROLES.REPORTING_MANAGER, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )
    strategy_one.setKeeper(keeper, sender=management)
    keeper.addNewStrategy(strategy_one, sender=daddy)
    keeper.setKeeper(yield_manager, True, sender=daddy)
    yield_manager.setProposer(user, True, sender=daddy)

    loss = amount // 10

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    generic_debt_allocator.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    # Record strategy loss
    asset.transfer(user, loss, sender=strategy_one)
    strategy_one.report(sender=keeper)

    to_move = amount
    allocation = [(strategy_one, amount - to_move), (strategy_two, to_move)]

    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    assert len(list(tx.decode_logs(vault.StrategyReported))) == 1
    assert vault.totalAssets() < amount

    assert generic_debt_allocator.shouldUpdateDebt(strategy_two)[0] == False
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    assert bool == True

    generic_debt_allocator.update_debt(strategy_one, amount - to_move, sender=daddy)

    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy_two, to_move - loss)


def test_validate_allocation(
    apr_oracle,
    yield_manager,
    vault,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    strategy_one = deploy_mock_tokenized("One")
    strategy_two = deploy_mock_tokenized("two")
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    # Can validate the allocation with no strategies when all is idle
    assert vault.totalIdle() == amount

    assert yield_manager.validateAllocation(vault, [])
    assert yield_manager.validateAllocation(vault, [(strategy_one, amount)])
    assert yield_manager.validateAllocation(
        vault, [(strategy_one, amount), (strategy_two, 0)]
    )

    generic_debt_allocator.update_debt(strategy_one, amount // 2, sender=daddy)

    assert yield_manager.validateAllocation(vault, []) == False
    assert yield_manager.validateAllocation(vault, [(strategy_one, amount)])
    assert yield_manager.validateAllocation(
        vault, [(strategy_one, amount), (strategy_two, 0)]
    )

    # Now will be false
    generic_debt_allocator.update_debt(
        strategy_two, vault.totalIdle() // 2, sender=daddy
    )

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
    keeper,
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
    keeper,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)
    generic_debt_allocator.setKeeper(yield_manager, True, sender=daddy)
    generic_debt_allocator.setMinimumChange(1, sender=daddy)
    vault.set_role(yield_manager, ROLES.REPORTING_MANAGER, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    # Can just pass in one at to allocate
    allocation = [(strategy_two, amount)]

    with ape.reverts("!governance"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=user)

    yield_manager.setProposer(user, True, sender=daddy)

    # Still cant allocate even with allocator role
    with ape.reverts("!governance"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=user)

    tx = yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    assert generic_debt_allocator.shouldUpdateDebt(strategy_one)[0] == False
    (bool, bytes) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool == True
    assert bytes == vault.update_debt.encode_input(strategy_two, amount)

    generic_debt_allocator.update_debt(strategy_two, amount, sender=daddy)

    allocation = [(strategy_one, amount)]
    with ape.reverts("ratio too high"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    # strategy one is now earning more
    strategy_one.setApr(int(1.5e17), sender=management)

    # only move part
    to_move = amount // 2
    # will revert if in the wrong order
    allocation = [(strategy_one, to_move), (strategy_two, amount - to_move)]
    with ape.reverts("ratio too high"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    allocation = [(strategy_two, amount - to_move), (strategy_one, to_move)]
    tx = yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    assert generic_debt_allocator.configs(strategy_two).targetRatio != MAX_BPS
    assert generic_debt_allocator.configs(strategy_one).targetRatio != 0
    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    (bool_two, bytes_two) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool_one == False
    assert bool_two == True
    assert bytes_two == vault.update_debt.encode_input(
        strategy_two.address, amount - to_move
    )

    generic_debt_allocator.update_debt(strategy_two, amount - to_move, sender=daddy)

    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    assert bool_one == True
    assert bytes_one == vault.update_debt.encode_input(strategy_one, to_move)

    generic_debt_allocator.update_debt(strategy_one, to_move, sender=daddy)

    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    (bool_two, bytes_two) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool_one == False
    assert bool_two == False

    # Try and move all
    allocation = [(strategy_two, 0), (strategy_one, amount)]
    # Strategy manager isnt the strategies management
    with ape.reverts("!keeper"):
        yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    strategy_two.setKeeper(keeper, sender=management)
    keeper.addNewStrategy(strategy_two, sender=daddy)
    keeper.setKeeper(yield_manager, True, sender=daddy)

    tx = yield_manager.updateAllocationPermissioned(vault, allocation, sender=daddy)

    assert len(list(tx.decode_logs(strategy_two.Reported))) == 1

    assert generic_debt_allocator.configs(strategy_two).targetRatio == 0
    assert generic_debt_allocator.configs(strategy_one).targetRatio == MAX_BPS
    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    (bool_two, bytes_two) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool_one == False
    assert bool_two == True
    assert bytes_two == vault.update_debt.encode_input(strategy_two.address, 0)

    generic_debt_allocator.update_debt(strategy_two, 0, sender=daddy)

    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    assert bool_one == True
    assert bytes_one == vault.update_debt.encode_input(strategy_one, amount)

    generic_debt_allocator.update_debt(strategy_one, amount, sender=daddy)

    (bool_one, bytes_one) = generic_debt_allocator.shouldUpdateDebt(strategy_one)
    (bool_two, bytes_two) = generic_debt_allocator.shouldUpdateDebt(strategy_two)
    assert bool_one == False
    assert bool_two == False

    assert vault.totalIdle() == 0
    assert vault.totalDebt() == amount
    assert vault.totalAssets() == amount
    assert vault.strategies(strategy_one).current_debt == amount
    assert vault.strategies(strategy_two).current_debt == 0


def test_update_allocation__max_withdraw(
    apr_oracle,
    yield_manager,
    vault,
    management,
    keeper,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)
    generic_debt_allocator.setKeeper(yield_manager, True, sender=daddy)
    generic_debt_allocator.setMinimumChange(1, sender=daddy)
    vault.add_role(yield_manager, ROLES.REPORTING_MANAGER, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )
    strategy_one.setKeeper(keeper, sender=management)
    keeper.addNewStrategy(strategy_one, sender=daddy)
    keeper.setKeeper(yield_manager, True, sender=daddy)
    yield_manager.setProposer(user, True, sender=daddy)

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    generic_debt_allocator.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    limit = amount // 2

    # Simulate a max withdraw limit
    strategy_one.setLimit(limit, sender=daddy)

    # Try and move all
    allocation = [(strategy_one, 0), (strategy_two, amount)]

    with ape.reverts("max withdraw"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    # Can withdraw up to the limit
    allocation = [(strategy_one, amount - limit), (strategy_two, limit)]
    yield_manager.updateAllocation(vault, allocation, sender=user)

    # lower the limit to 0
    strategy_one.setLimit(0, sender=daddy)

    # Now can move everything.
    allocation = [(strategy_one, 0), (strategy_two, amount)]
    yield_manager.updateAllocation(vault, allocation, sender=user)


def test_update_allocation__max_deposit(
    apr_oracle,
    yield_manager,
    vault,
    management,
    keeper,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)
    generic_debt_allocator.setKeeper(yield_manager, True, sender=daddy)
    generic_debt_allocator.setMinimumChange(1, sender=daddy)
    vault.add_role(yield_manager, ROLES.REPORTING_MANAGER, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )
    strategy_one.setKeeper(keeper, sender=management)
    keeper.addNewStrategy(strategy_one, sender=daddy)
    keeper.setKeeper(yield_manager, True, sender=daddy)
    yield_manager.setProposer(user, True, sender=daddy)

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    generic_debt_allocator.update_debt(strategy_one, amount, sender=daddy)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == amount
    assert vault.strategies(strategy_one).current_debt == amount

    limit = amount // 2

    # Simulate a max deposit limit
    strategy_two.setMaxDebt(limit, sender=daddy)

    # Try and move all
    allocation = [(strategy_one, 0), (strategy_two, amount)]

    with ape.reverts("max deposit"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    # Can deposit up to the limit
    allocation = [(strategy_one, amount - limit), (strategy_two, limit)]
    yield_manager.updateAllocation(vault, allocation, sender=user)

    # Increase the limit
    strategy_two.setMaxDebt(2**256 - 1, sender=daddy)

    # Now can move everything.
    allocation = [(strategy_one, 0), (strategy_two, amount)]
    yield_manager.updateAllocation(vault, allocation, sender=user)


def test_update_allocation__min_idle(
    apr_oracle,
    yield_manager,
    vault,
    management,
    keeper,
    daddy,
    user,
    amount,
    asset,
    deploy_mock_tokenized,
    generic_debt_allocator,
):
    # Strategy two will have the higher apr
    strategy_one = deploy_mock_tokenized("One", int(1e16))
    strategy_two = deploy_mock_tokenized("two", int(1e17))
    setup_vault(vault, [strategy_one, strategy_two], apr_oracle, daddy)
    yield_manager.setVaultAllocator(vault, generic_debt_allocator, sender=daddy)
    generic_debt_allocator.setKeeper(yield_manager, True, sender=daddy)
    generic_debt_allocator.setMinimumChange(1, sender=daddy)
    vault.add_role(yield_manager, ROLES.REPORTING_MANAGER, sender=daddy)
    vault.set_role(
        generic_debt_allocator,
        ROLES.DEBT_MANAGER | ROLES.REPORTING_MANAGER,
        sender=daddy,
    )
    strategy_one.setKeeper(keeper, sender=management)
    keeper.addNewStrategy(strategy_one, sender=daddy)
    keeper.setKeeper(yield_manager, True, sender=daddy)
    yield_manager.setProposer(user, True, sender=daddy)

    asset.approve(vault, amount, sender=user)
    vault.deposit(amount, user, sender=user)

    assert vault.totalAssets() == amount
    assert vault.totalDebt() == 0

    min_idle = amount // 2

    # add a minimum total idle requirement
    vault.set_minimum_total_idle(min_idle, sender=daddy)

    # Try and move all
    allocation = [(strategy_one, amount)]

    with ape.reverts("min idle"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    # Even just over the limit reverts.
    allocation = [(strategy_one, int(amount - min_idle + 1e18))]

    with ape.reverts("min idle"):
        yield_manager.updateAllocation(vault, allocation, sender=user)

    # Can deposit up to the limit
    allocation = [(strategy_one, amount - min_idle)]
    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatios))[0]
    assert event.newTargetRatio == 5_000

    # lower the min idle to 0
    vault.set_minimum_total_idle(0, sender=daddy)

    # Now can move everything.
    allocation = [(strategy_one, 0), (strategy_two, amount)]
    tx = yield_manager.updateAllocation(vault, allocation, sender=user)

    event = list(tx.decode_logs(generic_debt_allocator.UpdateStrategyDebtRatios))

    assert len(event) == 2
    assert event[0].newTargetRatio == 0
    assert event[1].newTargetRatio == 10_000
