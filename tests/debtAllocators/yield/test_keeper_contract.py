import ape
from ape import chain, project
from utils.constants import ZERO_ADDRESS, MAX_INT, ROLES


def test_keeper_setup(keeper, mock_tokenized, daddy, yield_manager):
    assert keeper.strategyOwner(mock_tokenized) == ZERO_ADDRESS
    assert keeper.keepers(yield_manager) == False
    assert keeper.governance() == daddy


def test_add_new_strategy(keeper, mock_tokenized, daddy, yield_manager, management):
    assert keeper.strategyOwner(mock_tokenized) == ZERO_ADDRESS
    assert keeper.keepers(yield_manager) == False

    with ape.reverts("!governance"):
        keeper.addNewStrategy(mock_tokenized, sender=management)

    with ape.reverts("!keeper"):
        keeper.addNewStrategy(mock_tokenized, sender=daddy)

    mock_tokenized.setKeeper(keeper, sender=management)

    tx = keeper.addNewStrategy(mock_tokenized, sender=daddy)

    assert mock_tokenized.keeper() == keeper

    event = list(tx.decode_logs(keeper.StrategyAdded))[0]

    assert event.strategy == mock_tokenized
    assert event.owner == management

    assert keeper.strategyOwner(mock_tokenized) == management

    # cannot add it again
    with ape.reverts("already active"):
        keeper.addNewStrategy(mock_tokenized, sender=daddy)


def test_remove_strategy(
    keeper, mock_tokenized, yield_manager, management, user, daddy
):
    # Will revert on modifier if not yet added.
    with ape.reverts("!owner"):
        keeper.removeStrategy(mock_tokenized, sender=management)

    mock_tokenized.setKeeper(keeper, sender=management)

    keeper.addNewStrategy(mock_tokenized, sender=daddy)

    assert mock_tokenized.keeper() == keeper
    assert keeper.strategyOwner(mock_tokenized) == management

    with ape.reverts("!owner"):
        keeper.removeStrategy(mock_tokenized, sender=user)

    tx = keeper.removeStrategy(mock_tokenized, sender=management)

    event = list(tx.decode_logs(keeper.StrategyRemoved))[0]

    assert event.strategy == mock_tokenized

    assert keeper.strategyOwner(mock_tokenized) == ZERO_ADDRESS
    assert mock_tokenized.management() == management


def test_update_owner(keeper, mock_tokenized, yield_manager, management, user, daddy):
    with ape.reverts("!owner"):
        keeper.updateStrategyOwner(mock_tokenized, user, sender=management)

    mock_tokenized.setKeeper(keeper, sender=management)

    keeper.addNewStrategy(mock_tokenized, sender=daddy)

    assert mock_tokenized.keeper() == keeper
    assert keeper.strategyOwner(mock_tokenized) == management

    with ape.reverts("!owner"):
        keeper.updateStrategyOwner(mock_tokenized, user, sender=user)

    with ape.reverts("bad address"):
        keeper.updateStrategyOwner(mock_tokenized, ZERO_ADDRESS, sender=management)

    with ape.reverts("bad address"):
        keeper.updateStrategyOwner(mock_tokenized, mock_tokenized, sender=management)

    with ape.reverts("bad address"):
        keeper.updateStrategyOwner(mock_tokenized, keeper, sender=management)

    keeper.updateStrategyOwner(mock_tokenized, user, sender=management)

    assert keeper.strategyOwner(mock_tokenized) == user
    assert mock_tokenized.keeper() == keeper


def test_report(keeper, mock_tokenized, management, yield_manager, asset, user, daddy):
    mock_tokenized.setKeeper(keeper, sender=management)

    keeper.addNewStrategy(mock_tokenized, sender=daddy)

    assert mock_tokenized.keeper() == keeper
    assert keeper.strategyOwner(mock_tokenized) == management

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
    assert current_unlock_time == 0
    assert mock_tokenized.pricePerShare() == 10 ** asset.decimals()

    with ape.reverts("!keeper"):
        keeper.report(mock_tokenized, sender=yield_manager)

    keeper.setKeeper(yield_manager, True, sender=daddy)

    keeper.report(mock_tokenized, sender=yield_manager)

    # Profit should be fully unlocked
    assert mock_tokenized.totalAssets() == to_deposit + profit
    assert mock_tokenized.totalSupply() == to_deposit
    assert mock_tokenized.pricePerShare() > 10 ** asset.decimals()


def test_tend(keeper, mock_tokenized, management, yield_manager, asset, user, daddy):
    mock_tokenized.setKeeper(keeper, sender=management)

    keeper.addNewStrategy(mock_tokenized, sender=daddy)

    assert mock_tokenized.keeper() == keeper
    assert keeper.strategyOwner(mock_tokenized) == management

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

    with ape.reverts("!keeper"):
        keeper.tend(mock_tokenized, sender=yield_manager)

    keeper.setKeeper(yield_manager, True, sender=daddy)

    keeper.tend(mock_tokenized, sender=yield_manager)
