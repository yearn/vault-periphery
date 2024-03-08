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


def test_unwrap(
    splitter, daddy, vault, mock_tokenized, deploy_mock_tokenized, asset, user, amount
):
    assert splitter.manager() == daddy

    second_strategy = deploy_mock_tokenized()

    amount = amount // 3

    asset.approve(vault, amount, sender=user)
    asset.approve(mock_tokenized, amount, sender=user)
    asset.approve(second_strategy, amount, sender=user)

    vault.deposit(amount, splitter, sender=user)
    mock_tokenized.deposit(amount, splitter, sender=user)
    second_strategy.deposit(amount, splitter, sender=user)

    assert vault.balanceOf(splitter) == amount
    assert mock_tokenized.balanceOf(splitter) == amount
    assert second_strategy.balanceOf(splitter) == amount
    assert asset.balanceOf(splitter) == 0

    with ape.reverts("!allowed"):
        splitter.unwrapVault(second_strategy, sender=user)

    splitter.unwrapVault(second_strategy, sender=daddy)

    assert vault.balanceOf(splitter) == amount
    assert mock_tokenized.balanceOf(splitter) == amount
    assert second_strategy.balanceOf(splitter) == 0
    assert asset.balanceOf(splitter) == amount

    vaults = [vault, mock_tokenized]

    with ape.reverts("!allowed"):
        splitter.unwrapVaults(vaults, sender=user)

    splitter.unwrapVaults(vaults, sender=daddy)

    assert vault.balanceOf(splitter) == 0
    assert mock_tokenized.balanceOf(splitter) == 0
    assert second_strategy.balanceOf(splitter) == 0
    assert asset.balanceOf(splitter) == amount * 3


def test_distribute(
    splitter,
    daddy,
    vault,
    mock_tokenized,
    deploy_mock_tokenized,
    asset,
    user,
    management,
    brain,
    amount,
):
    assert splitter.manager() == daddy
    recipeint = management
    splitee = brain
    split = 5_000

    second_strategy = deploy_mock_tokenized()

    amount = amount // 4

    asset.approve(vault, amount, sender=user)
    asset.approve(mock_tokenized, amount, sender=user)
    asset.approve(second_strategy, amount, sender=user)

    vault.deposit(amount, splitter, sender=user)
    mock_tokenized.deposit(amount, splitter, sender=user)
    second_strategy.deposit(amount, splitter, sender=user)

    assert vault.balanceOf(splitter) == amount
    assert vault.balanceOf(recipeint) == 0
    assert vault.balanceOf(splitee) == 0

    assert mock_tokenized.balanceOf(splitter) == amount
    assert mock_tokenized.balanceOf(recipeint) == 0
    assert mock_tokenized.balanceOf(splitee) == 0

    assert second_strategy.balanceOf(splitter) == amount
    assert second_strategy.balanceOf(recipeint) == 0
    assert second_strategy.balanceOf(splitee) == 0

    with ape.reverts("!allowed"):
        splitter.distributeToken(second_strategy, sender=user)

    splitter.distributeToken(second_strategy, sender=daddy)

    assert second_strategy.balanceOf(splitter) == 0
    assert second_strategy.balanceOf(recipeint) == amount / 2
    assert second_strategy.balanceOf(splitee) == amount / 2

    vaults = [vault, mock_tokenized]

    with ape.reverts("!allowed"):
        splitter.distributeTokens(vaults, sender=user)

    splitter.distributeTokens(vaults, sender=daddy)

    assert vault.balanceOf(splitter) == 0
    assert vault.balanceOf(recipeint) == amount / 2
    assert vault.balanceOf(splitee) == amount / 2

    assert mock_tokenized.balanceOf(splitter) == 0
    assert mock_tokenized.balanceOf(recipeint) == amount / 2
    assert mock_tokenized.balanceOf(splitee) == amount / 2


def test_auction(
    splitter,
    daddy,
    vault,
    mock_tokenized,
    deploy_mock_tokenized,
    asset,
    user,
    management,
    brain,
    amount,
):
    assert splitter.manager() == daddy
    auction = user

    second_strategy = deploy_mock_tokenized()

    amount = amount // 4

    asset.approve(vault, amount, sender=user)
    asset.approve(mock_tokenized, amount, sender=user)
    asset.approve(second_strategy, amount, sender=user)

    vault.deposit(amount, splitter, sender=user)
    mock_tokenized.deposit(amount, splitter, sender=user)
    second_strategy.deposit(amount, splitter, sender=user)

    assert vault.balanceOf(splitter) == amount
    assert vault.balanceOf(auction) == 0

    assert mock_tokenized.balanceOf(splitter) == amount
    assert mock_tokenized.balanceOf(auction) == 0

    assert second_strategy.balanceOf(splitter) == amount
    assert second_strategy.balanceOf(auction) == 0

    with ape.reverts("!allowed"):
        splitter.fundAuction(second_strategy, sender=user)

    with ape.reverts():
        splitter.fundAuction(second_strategy, sender=daddy)

    splitter.setAuction(auction, sender=daddy)

    splitter.fundAuction(second_strategy, sender=daddy)

    assert second_strategy.balanceOf(splitter) == 0
    assert second_strategy.balanceOf(auction) == amount

    vaults = [vault, mock_tokenized]

    with ape.reverts("!allowed"):
        splitter.fundAuctions(vaults, sender=user)

    splitter.fundAuctions(vaults, sender=daddy)

    assert vault.balanceOf(splitter) == 0
    assert vault.balanceOf(auction) == amount

    assert mock_tokenized.balanceOf(splitter) == 0
    assert mock_tokenized.balanceOf(auction) == amount


def test_setters(splitter, daddy, user, brain, management):
    recipeint = management
    splitee = brain
    split = 5_000
    max_loss = 1

    new_recipient = user

    assert splitter.managerRecipient() == recipeint

    with ape.reverts("!manager"):
        splitter.setMangerRecipient(new_recipient, sender=brain)

    assert splitter.managerRecipient() == recipeint

    tx = splitter.setMangerRecipient(new_recipient, sender=daddy)

    assert splitter.managerRecipient() == new_recipient
    assert (
        list(tx.decode_logs(splitter.UpdateManagerRecipient))[0].newManagerRecipient
        == new_recipient
    )

    new_splitee = user

    assert splitter.splitee() == splitee

    with ape.reverts("!splitee"):
        splitter.setSplitee(new_splitee, sender=daddy)

    assert splitter.splitee() == splitee

    tx = splitter.setSplitee(new_splitee, sender=brain)

    assert splitter.splitee() == new_splitee
    assert list(tx.decode_logs(splitter.UpdateSplitee))[0].newSplitee == new_splitee

    new_split = 123

    assert splitter.split() == split

    with ape.reverts("!manager"):
        splitter.setSplit(new_split, sender=brain)

    assert splitter.split() == split

    tx = splitter.setSplit(new_split, sender=daddy)

    assert splitter.split() == new_split
    assert list(tx.decode_logs(splitter.UpdateSplit))[0].newSplit == new_split

    new_max_loss = 123

    assert splitter.maxLoss() == max_loss

    with ape.reverts("!manager"):
        splitter.setMaxLoss(new_max_loss, sender=brain)

    assert splitter.maxLoss() == max_loss

    tx = splitter.setMaxLoss(new_split, sender=daddy)

    assert splitter.maxLoss() == new_max_loss
    assert list(tx.decode_logs(splitter.UpdateMaxLoss))[0].newMaxLoss == new_max_loss

    new_auction = user

    assert splitter.auction() == ZERO_ADDRESS

    with ape.reverts("!manager"):
        splitter.setAuction(new_auction, sender=brain)

    assert splitter.auction() == ZERO_ADDRESS

    tx = splitter.setAuction(new_auction, sender=daddy)

    assert splitter.auction() == new_auction
    assert list(tx.decode_logs(splitter.UpdateAuction))[0].newAuction == new_auction
