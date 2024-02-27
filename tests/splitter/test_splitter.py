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
