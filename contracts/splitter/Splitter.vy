# @version 0.3.7

interface IVault:
    def asset() -> address: view
    def balanceOf(owner: address) -> uint256: view
    def redeem(shares: uint256, receiver: address, owner: address, max_loss: uint256) -> uint256: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable

MAX_BPS: constant(uint256) = 10_000
MAX_ARRAY_SIZE: public(constant(uint256)) = 20

name: public(String[64])

# Bid daddy yankee in charge of the splitter
manager: public(address)
# Address to receive the managers shares
managerRecipient: public(address)
# Team to receive the rest of the split
splitee: public(address)

# Percent that is sent to `managerRecipient`
split: public(uint256)
# Max loss to use on vault redeems
maxLoss: public(uint256)

@external
def initialize(
    name: String[64], 
    manager: address,
    manager_recipient: address,
    splitee: address,
    original_split: uint256
):
    assert self.manager == empty(address), "initialized"
    assert manager != empty(address), "ZERO_ADDRESS"
    assert manager_recipient != empty(address), "ZERO_ADDRESS"
    assert splitee != empty(address), "ZERO_ADDRESS"
    assert original_split <= MAX_BPS, "MAX_BPS"
    assert original_split != 0, "zero split"

    self.name = name
    self.manager = manager
    self.managerRecipient = manager_recipient
    self.splitee = splitee
    self.split = original_split
    self.maxLoss = 1


####### UNWRAP VAULT TOKENS ######

@external
def unwrapVault(vault: address):
    assert msg.sender == self.splitee or msg.sender == self.manager, "!allowed"
    self._unwrapVault(vault, self.maxLoss)

@external
def unwrapVaults(vaults: DynArray[address, MAX_ARRAY_SIZE]):
    assert msg.sender == self.splitee or msg.sender == self.manager, "!allowed"

    max_loss: uint256 = self.maxLoss

    for vault in vaults:
        self._unwrapVault(vault, max_loss)

@internal
def _unwrapVault(vault: address, max_loss: uint256):
    vault_balance: uint256 = IVault(vault).balanceOf(self)
    IVault(vault).redeem(vault_balance, self, self, max_loss)

###### DISTRIBUTE TOKENS ######

# split one token
@external 
def distributeToken(token: address):
    splitee: address = self.splitee
    assert msg.sender == splitee or msg.sender == self.manager, "!allowed"
    self._distribute(token, self.split, self.managerRecipient, splitee)

# split an array of tokens
@external
def distributeTokens(tokens: DynArray[address, MAX_ARRAY_SIZE]):
    splitee: address = self.splitee
    assert msg.sender == splitee or msg.sender == self.manager, "!allowed"

    # Cache the split storage variables
    split: uint256 = self.split
    manager_recipient: address = self.managerRecipient

    for token in tokens:
        self._distribute(token, split, manager_recipient, splitee)

@internal
def _distribute(token: address, split: uint256, manager_recipient: address, splitee: address):
    current_balance: uint256 = IVault(token).balanceOf(self)
    manager_split: uint256 = unsafe_div(unsafe_mul(current_balance, split), MAX_BPS)
    assert IVault(token).transfer(manager_recipient, manager_split, default_return_value=True), "transfer failed"
    assert IVault(token).transfer(splitee, unsafe_sub(current_balance, manager_split), default_return_value=True), "transfer failed"

###### SETTERS ######

# Update Split
@external
def setSplit(new_split: uint256):
    assert msg.sender == self.manager, "!manager"
    assert new_split <= MAX_BPS, "MAX_BPS"
    assert new_split != 0, "zero split"

    self.split = new_split

# update recipients
@external
def setMangerRecipient(new_recipient: address):
    assert msg.sender == self.manager, "!manager"
    assert new_recipient != empty(address), "ZERO_ADDRESS"

    self.managerRecipient = new_recipient

@external
def setSplitee(new_splitee: address):
    assert msg.sender == self.splitee, "!splitee"
    assert new_splitee != empty(address), "ZERO_ADDRESS"

    self.splitee = new_splitee

# Set max loss
@external
def setMaxLoss(new_max_loss: uint256):
    assert msg.sender == self.manager, "!manager"
    assert new_max_loss <= MAX_BPS, "MAX_BPS"

    self.maxLoss = new_max_loss
