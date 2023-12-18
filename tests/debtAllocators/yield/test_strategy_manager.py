import ape
from ape import chain, project
from utils.constants import ZERO_ADDRESS, MAX_INT, ROLES


def test_strategy_manager_setup(strategy_manager, mock_tokenized):
    assert strategy_manager.strategyInfo(mock_tokenized).active == False
    assert strategy_manager.strategyInfo(mock_tokenized).owner == ZERO_ADDRESS
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == ZERO_ADDRESS


def test_add_new_strategy(
    strategy_manager, mock_tokenized, daddy, yield_manager, management
):
    assert strategy_manager.strategyInfo(mock_tokenized).active == False
    assert strategy_manager.strategyInfo(mock_tokenized).owner == ZERO_ADDRESS
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == ZERO_ADDRESS

    with ape.reverts("!governance"):
        strategy_manager.manageNewStrategy(
            mock_tokenized, yield_manager, sender=management
        )

    with ape.reverts("!pending"):
        strategy_manager.manageNewStrategy(mock_tokenized, yield_manager, sender=daddy)

    mock_tokenized.setPendingManagement(strategy_manager, sender=management)

    tx = strategy_manager.manageNewStrategy(mock_tokenized, yield_manager, sender=daddy)

    assert mock_tokenized.management() == strategy_manager

    event = list(tx.decode_logs(strategy_manager.StrategyAdded))[0]

    assert event.strategy == mock_tokenized
    assert event.owner == management
    assert event.debtManager == yield_manager

    assert strategy_manager.strategyInfo(mock_tokenized).active == True
    assert strategy_manager.strategyInfo(mock_tokenized).owner == management
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == yield_manager

    # cannot add it again
    with ape.reverts("already active"):
        strategy_manager.manageNewStrategy(mock_tokenized, yield_manager, sender=daddy)


def test_remove_strategy(
    strategy_manager, mock_tokenized, yield_manager, management, user, daddy
):
    # Will revert on modifier if not yet added.
    with ape.reverts("!owner"):
        strategy_manager.removeManagement(mock_tokenized, user, sender=management)

    mock_tokenized.setPendingManagement(strategy_manager, sender=management)

    strategy_manager.manageNewStrategy(mock_tokenized, yield_manager, sender=daddy)

    assert mock_tokenized.management() == strategy_manager
    assert strategy_manager.strategyInfo(mock_tokenized).active == True
    assert strategy_manager.strategyInfo(mock_tokenized).owner == management
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == yield_manager

    with ape.reverts("!owner"):
        strategy_manager.removeManagement(mock_tokenized, user, sender=user)

    with ape.reverts("!owner"):
        strategy_manager.removeManagement(mock_tokenized, sender=user)

    with ape.reverts("bad address"):
        strategy_manager.removeManagement(
            mock_tokenized, ZERO_ADDRESS, sender=management
        )

    with ape.reverts("bad address"):
        strategy_manager.removeManagement(
            mock_tokenized, mock_tokenized, sender=management
        )

    with ape.reverts("bad address"):
        strategy_manager.removeManagement(
            mock_tokenized, strategy_manager, sender=management
        )

    tx = strategy_manager.removeManagement(mock_tokenized, user, sender=management)

    event = list(tx.decode_logs(strategy_manager.StrategyRemoved))[0]

    assert event.strategy == mock_tokenized
    assert event.newManager == user

    assert strategy_manager.strategyInfo(mock_tokenized).active == False
    assert strategy_manager.strategyInfo(mock_tokenized).owner == ZERO_ADDRESS
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == ZERO_ADDRESS

    assert mock_tokenized.management() == strategy_manager
    assert mock_tokenized.pendingManagement() == user
    mock_tokenized.acceptManagement(sender=user)
    assert mock_tokenized.management() == user


def test_update_owner(
    strategy_manager, mock_tokenized, yield_manager, management, user, daddy
):
    with ape.reverts("!owner"):
        strategy_manager.updateStrategyOwner(mock_tokenized, user, sender=management)

    mock_tokenized.setPendingManagement(strategy_manager, sender=management)

    strategy_manager.manageNewStrategy(mock_tokenized, yield_manager, sender=daddy)

    assert mock_tokenized.management() == strategy_manager
    assert strategy_manager.strategyInfo(mock_tokenized).active == True
    assert strategy_manager.strategyInfo(mock_tokenized).owner == management
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == yield_manager

    with ape.reverts("!owner"):
        strategy_manager.updateStrategyOwner(mock_tokenized, user, sender=user)

    with ape.reverts("bad address"):
        strategy_manager.updateStrategyOwner(
            mock_tokenized, ZERO_ADDRESS, sender=management
        )

    with ape.reverts("bad address"):
        strategy_manager.updateStrategyOwner(
            mock_tokenized, mock_tokenized, sender=management
        )

    with ape.reverts("bad address"):
        strategy_manager.updateStrategyOwner(
            mock_tokenized, strategy_manager, sender=management
        )

    strategy_manager.updateStrategyOwner(mock_tokenized, user, sender=management)

    assert strategy_manager.strategyInfo(mock_tokenized).active == True
    assert strategy_manager.strategyInfo(mock_tokenized).owner == user
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == yield_manager
    assert mock_tokenized.management() == strategy_manager


def test_update_debt_manager(
    strategy_manager, mock_tokenized, yield_manager, management, user, daddy
):
    mock_tokenized.setPendingManagement(strategy_manager, sender=management)

    strategy_manager.manageNewStrategy(mock_tokenized, yield_manager, sender=daddy)

    assert mock_tokenized.management() == strategy_manager
    assert strategy_manager.strategyInfo(mock_tokenized).active == True
    assert strategy_manager.strategyInfo(mock_tokenized).owner == management
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == yield_manager

    with ape.reverts("!owner"):
        strategy_manager.updateDebtManager(mock_tokenized, user, sender=user)

    strategy_manager.updateDebtManager(mock_tokenized, user, sender=management)

    assert strategy_manager.strategyInfo(mock_tokenized).active == True
    assert strategy_manager.strategyInfo(mock_tokenized).owner == management
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == user
    assert mock_tokenized.management() == strategy_manager


def test_record_full_profit(
    strategy_manager, mock_tokenized, management, yield_manager, asset, user, daddy
):
    mock_tokenized.setProfitMaxUnlockTime(int(60 * 60 * 24), sender=management)
    mock_tokenized.setPendingManagement(strategy_manager, sender=management)

    strategy_manager.manageNewStrategy(mock_tokenized, yield_manager, sender=daddy)

    assert mock_tokenized.management() == strategy_manager
    assert strategy_manager.strategyInfo(mock_tokenized).active == True
    assert strategy_manager.strategyInfo(mock_tokenized).owner == management
    assert strategy_manager.strategyInfo(mock_tokenized).debtManager == yield_manager

    # deposit into the strategy
    to_deposit = asset.balanceOf(user) // 2
    profit = asset.balanceOf(user) - to_deposit

    asset.approve(mock_tokenized, to_deposit, sender=user)
    mock_tokenized.deposit(to_deposit, user, sender=user)

    assert mock_tokenized.totalAssets() == to_deposit
    assert mock_tokenized.totalSupply() == to_deposit

    # simulate profit
    asset.transfer(mock_tokenized, profit, sender=user)

    assert mock_tokenized.totalAssets() == to_deposit
    assert mock_tokenized.totalSupply() == to_deposit
    current_unlock_time = mock_tokenized.profitMaxUnlockTime()
    assert current_unlock_time != 0
    assert mock_tokenized.pricePerShare() == 10 ** asset.decimals()

    with ape.reverts("!debt manager"):
        strategy_manager.reportFullProfit(mock_tokenized, sender=user)

    strategy_manager.reportFullProfit(mock_tokenized, sender=yield_manager)

    # Profit should be fully unlocked
    assert mock_tokenized.totalAssets() == to_deposit + profit
    assert mock_tokenized.totalSupply() == to_deposit
    assert current_unlock_time == mock_tokenized.profitMaxUnlockTime()
    assert mock_tokenized.pricePerShare() > 10 ** asset.decimals()


def test_forward_call(
    strategy_manager, mock_tokenized, management, yield_manager, asset, user, daddy
):
    mock_tokenized.setPendingManagement(strategy_manager, sender=management)

    strategy_manager.manageNewStrategy(mock_tokenized, yield_manager, sender=daddy)

    assert mock_tokenized.profitMaxUnlockTime() == 0
    assert mock_tokenized.performanceFee() == 0

    # Yield manager can change profit max unlock
    new_unlock_time = int(69)
    calldata = mock_tokenized.setProfitMaxUnlockTime.encode_input(int(new_unlock_time))

    with ape.reverts("!debt manager"):
        strategy_manager.forwardCall(mock_tokenized, calldata, sender=user)

    tx = strategy_manager.forwardCall(mock_tokenized, calldata, sender=management)

    event = list(tx.decode_logs(mock_tokenized.UpdateProfitMaxUnlockTime))[0]
    assert event.newProfitMaxUnlockTime == new_unlock_time
    assert mock_tokenized.profitMaxUnlockTime() == new_unlock_time

    new_unlock_time = int(6699)
    calldata = mock_tokenized.setProfitMaxUnlockTime.encode_input(int(new_unlock_time))

    tx = strategy_manager.forwardCall(mock_tokenized, calldata, sender=yield_manager)

    event = list(tx.decode_logs(mock_tokenized.UpdateProfitMaxUnlockTime))[0]
    assert event.newProfitMaxUnlockTime == new_unlock_time
    assert mock_tokenized.profitMaxUnlockTime() == new_unlock_time

    # Only management can change a performance fee.
    new_fee = int(2_000)
    calldata = mock_tokenized.setPerformanceFee.encode_input(new_fee)

    with ape.reverts("!owner"):
        strategy_manager.forwardCall(mock_tokenized, calldata, sender=user)

    with ape.reverts("!owner"):
        strategy_manager.forwardCall(mock_tokenized, calldata, sender=yield_manager)

    tx = strategy_manager.forwardCall(mock_tokenized, calldata, sender=management)

    event = list(tx.decode_logs(mock_tokenized.UpdatePerformanceFee))[0]
    assert event.newPerformanceFee == new_fee
    assert mock_tokenized.performanceFee() == new_fee

    # We get the correct return data
    new_unlock_time = int(1e25)
    calldata = mock_tokenized.setProfitMaxUnlockTime.encode_input(int(new_unlock_time))

    with ape.reverts("too long"):
        strategy_manager.forwardCall(mock_tokenized, calldata, sender=yield_manager)


def test_forward_calls(
    strategy_manager, mock_tokenized, management, yield_manager, daddy, user
):
    mock_tokenized.setPendingManagement(strategy_manager, sender=management)

    strategy_manager.manageNewStrategy(mock_tokenized, yield_manager, sender=daddy)

    assert mock_tokenized.profitMaxUnlockTime() == 0
    assert mock_tokenized.performanceFee() == 0

    # Yield manager can change profit max unlock
    new_unlock_time = int(69)
    new_fee = int(2_000)
    calldatas = [
        mock_tokenized.setProfitMaxUnlockTime.encode_input(int(new_unlock_time)),
        mock_tokenized.setPerformanceFee.encode_input(new_fee),
    ]

    # Only management can change a performance fee.
    with ape.reverts("!debt manager"):
        strategy_manager.forwardCalls(mock_tokenized, calldatas, sender=user)

    with ape.reverts("!owner"):
        strategy_manager.forwardCalls(mock_tokenized, calldatas, sender=yield_manager)

    tx = strategy_manager.forwardCalls(mock_tokenized, calldatas, sender=management)

    event = list(tx.decode_logs(mock_tokenized.UpdatePerformanceFee))[0]
    assert event.newPerformanceFee == new_fee
    assert mock_tokenized.performanceFee() == new_fee

    event = list(tx.decode_logs(mock_tokenized.UpdateProfitMaxUnlockTime))[0]
    assert event.newProfitMaxUnlockTime == new_unlock_time
    assert mock_tokenized.profitMaxUnlockTime() == new_unlock_time
