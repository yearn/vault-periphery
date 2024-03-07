import ape
from ape import chain
from utils.constants import ZERO_ADDRESS, MAX_INT


def test_split_setup(splitter_factory, splitter, daddy, brain, management):
    assert splitter_factory.ORIGINAL() != ZERO_ADDRESS
    assert splitter.address != ZERO_ADDRESS
    assert splitter.manager() == daddy
    assert splitter.managerRecipient() == management
    assert splitter.splitee() == brain
    assert splitter.split() == 5_000
    assert splitter.maxLoss() == 1
    assert splitter.auction() == ZERO_ADDRESS

def test_unwrap(splitter, daddy, vault, mock_tokenized, strategy, asset, user, amount):
    assert splitter.manager() == daddy

    amount = amount // 3

    asset.approve(vault, amount, sender=user)
    asset.approve(mock_tokenized, amount, sender=user)
    asset.approv(strategy, amount, sender=user)

    vault.deposit(amount, splitter, sender=user)
    mock_tokenized.deposit(amount, splitter, sender=user)
    strategy.deposit(amount, splitter, sender=user)

    assert vault.balanceOf(splitter) == amount
    assert mock_tokenized.balanceOf(splitter) == amount
    assert strategy.balanceOf(splitter) == amount
    assert asset.balanceOf(splitter) == 0

    with ape.reverts("!allowed"):
        splitter.unwrapVault(strategy, sender=user)

    splitter.unwrapVault(strategy, sender=daddy)

    assert vault.balanceOf(splitter) == 0
    assert mock_tokenized.balanceOf(splitter) == amount
    assert strategy.balanceOf(splitter) == amount
    assert asset.balanceOf(splitter) == amount

    vaults = [vault, mock_tokenized]

    with ape.reverts("!allowed"):
        splitter.unwrapVaults(vaults, sender=user)

    splitter.unwrapVaults(vaults, sender=daddy)

    assert vault.balanceOf(splitter) == 0
    assert mock_tokenized.balanceOf(splitter) == 0
    assert strategy.balanceOf(splitter) == 0
    assert asset.balanceOf(splitter) == amount * 3 