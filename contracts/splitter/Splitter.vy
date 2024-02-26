# @version 0.3.7

interface IVault:
    def asset() -> address: view
    def balanceOf(owner: address) -> uint256: view
    def redeem(shares: uint256, receiver: address, owner: address, max_loss: uint256) -> uint256: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable

event UpdateManagerRecipient:
    newManagerRecipient: indexed(address)

event UpdateSplitee:
    newSplitee: indexed(address)

event UpdateSplit:
    newSplit: uint256

event UpdateMaxLoss:
    newMaxLoss: uint256

event UpdateAuction:
    newAuction: address

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

# Address of the contract to conduct dutch auctions for token sales
auction: public(address)

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
    assert original_split != 0, "zero split"

    self.name = name
    self.manager = manager
    self.managerRecipient = manager_recipient
    self.splitee = splitee
    self.split = original_split
    self.maxLoss = 1


###### UNWRAP VAULT TOKENS ######

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
    manager_split: uint256 = current_balance
    
    if split != MAX_BPS:
        manager_split = unsafe_div(unsafe_mul(current_balance, split), MAX_BPS)
        self._transferERC20(token, splitee, unsafe_sub(current_balance, manager_split))

    self._transferERC20(token, manager_recipient, manager_split)

###### AUCTION INITIATORS ######

@external
def fundAuctions(tokens: DynArray[address, MAX_ARRAY_SIZE]):
    assert msg.sender == self.splitee or msg.sender == self.manager, "!allowed"
    auction: address = self.auction

    for token in tokens:
        amount: uint256 = IVault(token).balanceOf(self)
        self._transferERC20(token, auction, amount)

@external
def fundAuction(token: address, amount: uint256 = max_value(uint256)):
    assert msg.sender == self.splitee or msg.sender == self.manager, "!allowed"

    to_send: uint256 = amount
    if(amount == max_value(uint256)):
        to_send = IVault(token).balanceOf(self)

    self._transferERC20(token, self.auction, to_send)

@internal
def _transferERC20(token: address, recipient: address, amount: uint256):
    # Send tokens to the auction contract.
    assert IVault(token).transfer(recipient, amount, default_return_value=True), "transfer failed"

###### SETTERS ######

# update recipients
@external
def setMangerRecipient(new_recipient: address):
    assert msg.sender == self.manager, "!manager"
    assert new_recipient != empty(address), "ZERO_ADDRESS"

    self.managerRecipient = new_recipient

    log UpdateManagerRecipient(new_recipient)

@external
def setSplitee(new_splitee: address):
    assert msg.sender == self.splitee, "!splitee"
    assert new_splitee != empty(address), "ZERO_ADDRESS"

    self.splitee = new_splitee

    log UpdateSplitee(new_splitee)

# Update Split
@external
def setSplit(new_split: uint256):
    assert msg.sender == self.manager, "!manager"
    assert new_split != 0, "zero split"

    self.split = new_split

    log UpdateSplit(new_split)

# Set max loss
@external
def setMaxLoss(new_max_loss: uint256):
    assert msg.sender == self.manager, "!manager"
    assert new_max_loss <= MAX_BPS, "MAX_BPS"

    self.maxLoss = new_max_loss

    log UpdateMaxLoss(new_max_loss)

@external
def setAuction(new_auction: address):
    assert msg.sender == self.manager, "!manager"

    self.auction = new_auction