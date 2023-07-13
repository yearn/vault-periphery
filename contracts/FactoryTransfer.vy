# @version 0.3.7

interface IFactory:
    def governance() -> address: view
    def pending_governance() -> address: view
    def default_protocol_fee_config() -> (PFConfig): view
    def set_governance(new_governance: address): nonpayable
    def accept_governance(): nonpayable
    def set_protocol_fee_bps(new_protocol_fee_bps: uint16): nonpayable
    def set_protocol_fee_recipient(new_protocol_fee_recipient: address): nonpayable
    def set_custom_protocol_fee_bps(vault: address, new_custom_protocol_fee: uint16): nonpayable
    def remove_custom_protocol_fee(vault: address): nonpayable

struct PFConfig:
    # Percent of protocol's split of fees in Basis Points.
    fee_bps: uint16
    # Address the protocol fees get paid to.
    fee_recipient: address

FACTORY: immutable(address)
YCHAD:  immutable(address)
GOVERNANCE: immutable(address)
START: immutable(uint256)
DURATION: immutable(uint256)
DEFAULT_FEE: immutable(uint16)

@external
def __init__(
    factory: address,
    yChad: address,
    governance: address,
    duration: uint256,
    default_fee: uint16
):
    assert empty(address) not in [factory, yChad, governance], "ZERO ADDRESS"
    assert duration > 0

    if IFactory(factory).governance() != self:
        IFactory(factory).accept_governance()

    assert IFactory(factory).governance() == self, "not governance"
    assert IFactory(factory).default_protocol_fee_config().fee_recipient != empty(address), "no fee recipient"
    
    FACTORY = factory
    YCHAD = yChad
    GOVERNANCE = governance
    START = block.timestamp
    DURATION = duration
    DEFAULT_FEE = default_fee


# Set custom fees
@external
def set_custom_protocol_fee_bps(vault: address, new_custom_protocol_fee: uint16):
    assert msg.sender == YCHAD, "!yChad"
    IFactory(FACTORY).set_custom_protocol_fee_bps(vault, new_custom_protocol_fee)

@external
def remove_custom_protocol_fee(vault: address):
    assert msg.sender == YCHAD, "!yChad"
    IFactory(FACTORY).remove_custom_protocol_fee(vault)

# countdown
@external
@view
def time_remaining() -> uint256:
    end: uint256 = START + DURATION
    if end > block.timestamp:
        return end - block.timestamp
    else:
        return 0

# transfer ownerhsip
@external
def transfer_ownership():
    assert block.timestamp > START + DURATION, "not ready"

    # Set the desired Fee
    IFactory(FACTORY).set_protocol_fee_bps(DEFAULT_FEE)

    # Transfer Ownerhsip
    IFactory(FACTORY).set_governance(GOVERNANCE)