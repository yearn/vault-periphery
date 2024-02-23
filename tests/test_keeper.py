import ape
from ape import chain
from utils.constants import ZERO_ADDRESS, ROLES, MAX_INT


def test_keeper(daddy, keeper, vault, mock_tokenized, amount, user, asset, management):
    strategy = mock_tokenized
    # Revert on vault does not cause revert
    with ape.reverts("not allowed"):
        vault.process_report(strategy, sender=keeper)

    tx = keeper.process_report(vault, strategy, sender=user)

    profit, loss = tx.return_value
    assert profit == 0
    assert loss == 0

    vault.add_strategy(strategy, sender=daddy)
    vault.set_role(keeper, ROLES.REPORTING_MANAGER, sender=daddy)

    amount = amount // 2

    asset.approve(strategy, amount, sender=user)
    strategy.deposit(amount, vault, sender=user)

    tx = keeper.process_report(vault, strategy, sender=user)

    profit, loss = tx.return_value
    assert profit == amount
    assert loss == 0

    asset.transfer(strategy, amount, sender=user)

    strategy.setKeeper(user, sender=management)

    with ape.reverts("!keeper"):
        strategy.report(sender=keeper)

    tx = keeper.report(strategy, sender=user)

    profit, loss = tx.return_value
    assert profit == 0
    assert loss == 0

    strategy.setKeeper(keeper, sender=management)

    tx = keeper.report(strategy, sender=user)

    profit, loss = tx.return_value
    assert profit == amount
    assert loss == 0
