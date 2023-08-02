# @version 0.3.7

from vyper.interfaces import ERC20

### EVENTS ###
event UpdatedGovernanceRecipient:
    old_recipient: address
    new_recipient: address

event UpdatedTeamRecipient:
    old_recipient: address
    new_recipient: address

event NewTeamSplit:
    team_split: uint256

### CONSTANTS ###

# 100% in basis points.
MAX_BPS: constant(uint256) = 10_000

### IMMUTABLES ###

GOVERNANCE: public(immutable(address))
TEAM: public(immutable(address))

### STORAGE ###

name: public(String[64])

# Addresses to receive the shares when distributed.
governance_recipient: public(address)
team_recipient: public(address)

# Amount in Basis Points of the teams share.
team_split: public(uint256)

@external
def __init__(
    governance: address,
    team: address,
    governance_recipient: address,
    team_recipient: address,
    initial_split: uint256,
    name: String[64]
):
    assert governance != empty(address), "ZERO ADDRESS"
    assert team != empty(address), "ZERO ADDRESS"
    assert governance_recipient != empty(address), "ZERO ADDRESS"
    assert team_recipient != empty(address), "ZERO ADDRESS"

    GOVERNANCE = governance
    TEAM = team

    self.name = name
    self.governance_recipient = governance_recipient
    self.team_recipient = team_recipient
    self.team_split = initial_split


@external
def dispurse(token: address):
    assert msg.sender in [GOVERNANCE, TEAM], "!authorized"
    self._dispurse(token, ERC20(token).balanceOf(self))

@external
def dispurse_amount(token: address, amount: uint256):
    assert msg.sender in [GOVERNANCE, TEAM], "!authorized"
    self._dispurse(token, amount)


@internal
def _dispurse(token: address, amount: uint256):
    # Get the teams share based on split.
    team_share: uint256 = amount * self.team_split / MAX_BPS

    # Transfer teams split to the team set address
    assert ERC20(token).transfer(
        self.team_recipient, 
        team_share, 
        default_return_value=True
    ), "transfer failed"
    
    # Transfer the rest to Governance set address.
    assert ERC20(token).transfer(
        self.governance_recipient, 
        amount - team_share, 
        default_return_value=True
    ), "transfer failed"

@external
def set_governance_recipient(new_governance_recipient: address):
    assert msg.sender == GOVERNANCE, "!authorized"
    assert new_governance_recipient != empty(address), "ZERO ADDRESS"

    log UpdatedGovernanceRecipient(self.governance_recipient, new_governance_recipient)

    self.governance_recipient = new_governance_recipient


@external
def set_team_recipient(new_team_recipient: address):
    assert msg.sender == TEAM, "!authorized"
    assert new_team_recipient != empty(address), "ZERO ADDRESS"

    log UpdatedTeamRecipient(self.team_recipient, new_team_recipient)

    self.team_recipient = new_team_recipient

    
@external
def set_new_split(new_split: uint256):
    assert msg.sender == GOVERNANCE, "!authorized"
    assert new_split < 10_000, "too high"
    assert new_split != self.team_split, "same split"

    self.team_split = new_split

    log NewTeamSplit(new_split)
