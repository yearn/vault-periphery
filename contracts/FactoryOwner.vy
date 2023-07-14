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

# Address of the Factory this is holding ownership for
FACTORY: public(immutable(address))
# Address that can still set custom fees.
YCHAD:  public(immutable(address))
# Address to transfer governance of factory to at the end.
GOVERNANCE: public(immutable(address))
# Timestamp of when Governance will be transferred to "GOVERNANCE".
END: public(immutable(uint256))
# The default protocol fee that will be set before transferring governance.
DEFAULT_FEE: public(immutable(uint16))

@external
def __init__(
    factory: address,
    yChad: address,
    governance: address,
    duration: uint256,
    default_fee: uint16
):
    """
    @notice Will initialize the immutable variables for this factory owner.
    @param factory The factory for this contract to hold governance for.
    @param yChad The address that can set custom protocol fees.
    @param duration The lengh in seconds that this contract will hold governance for.
    @param default_fee The fee to set the default protocol fee to before transferring governance.
    """
    # Make sure none of the address's are 0x0.
    assert empty(address) not in [factory, yChad, governance], "ZERO ADDRESS"
    # Make sure we are actaully holding ownerhsip.
    assert duration > 0

    # We will likely need to accept governance in the two step proccess.
    if IFactory(factory).governance() != self:
        IFactory(factory).accept_governance()

    # Double check we have ownership rights.
    assert IFactory(factory).governance() == self, "not governance"
    # Cannot set custom or default protocol fees if their is no recipient set.
    assert IFactory(factory).default_protocol_fee_config().fee_recipient != empty(address), "no fee recipient"
    
    # Set the global variables.
    FACTORY = factory
    YCHAD = yChad
    GOVERNANCE = governance
    END = block.timestamp + duration
    DEFAULT_FEE = default_fee

@external
def set_custom_protocol_fee_bps(vault: address, new_custom_protocol_fee: uint16):
    """
    @notice Available to 'YCHAD' to set a custom protocol fee for a vault.
    @dev Will only work while this contract is the factories governance.
    @param vault Address of the vault to set the custom fee for.
    @param new_custom_protocol_fee The custom protocol fee
    """
    assert msg.sender == YCHAD, "!yChad"
    IFactory(FACTORY).set_custom_protocol_fee_bps(vault, new_custom_protocol_fee)

@external
def remove_custom_protocol_fee(vault: address):
    """
    @notice Available to `YCHAD` to remove a custom protocol fee.
    @dev Will only work while this contract is the factories governance.
    @param vault The address to remove the custom protocol fee for.
    """
    assert msg.sender == YCHAD, "!yChad"
    IFactory(FACTORY).remove_custom_protocol_fee(vault)

@view
@external
def time_remaining() -> uint256:
    """
    @notice Returns the seconds remaining before governance can be transferred.
    """
    if END > block.timestamp:
        return END - block.timestamp
    else:
        return 0

@external
def transfer_ownership():
    """
    @notice To set the pre-defined default protocol fee and transfer governance.
    @dev Can be called by anyone once the duration has passed.
    This will retain the governance role until the `GOVERNANCE` address accepts.
    """
    assert block.timestamp > END, "not ready"

    # Set the desired Fee
    IFactory(FACTORY).set_protocol_fee_bps(DEFAULT_FEE)

    # Transfer Ownerhsip
    IFactory(FACTORY).set_governance(GOVERNANCE)