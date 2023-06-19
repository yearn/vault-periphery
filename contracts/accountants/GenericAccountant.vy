# @version 0.3.7

from vyper.interfaces import ERC20

# INTERFACES #
struct StrategyParams:
    activation: uint256
    last_report: uint256
    current_debt: uint256
    max_debt: uint256

interface IVault:
    def asset() -> address: view
    def strategies(strategy: address) -> StrategyParams: view
    def redeem(shares: uint256, receiver: address, owner: address) -> uint256: nonpayable

# EVENTS #
event VaultChanged:
    vault: address
    change: ChangeType

event UpdateDefaultFeeConfig:
    default_fee_config: Fee

event SetFutureFeeManager:
    future_fee_manager: address

event NewFeeManager:
    fee_manager: address

event UpdateCustomFeeConfig:
    strategy: address
    custom_config: Fee

event DistributeRewards:
    token: address
    rewards: uint256

### ENUMS ###

enum ChangeType:
    ADDED
    REMOVED

### STRUCTS ###

struct Fee:
    management_fee: uint16
    performance_fee: uint16
    refund_ratio: uint16
    max_fee: uint16


### CONSTANTS ###

# 100% in basis points.
MAX_BPS: constant(uint256) = 10_000

# NOTE: A four-century period will be missing 3 of its 100 Julian leap years, leaving 97.
#       So the average year has 365 + 97/400 = 365.2425 days
#       ERROR(Julian): -0.0078
#       ERROR(Gregorian): -0.0003
#       A day = 24 * 60 * 60 sec = 86400 sec
#       365.2425 * 86400 = 31556952.0
SECS_PER_YEAR: constant(uint256) = 31_556_952  # 365.2425 days


### STORAGE ####

# Address in charge of the accountant.
fee_manager: public(address)
# Address to become the fee manager.
future_fee_manager: public(address)
# Mapping of vaults that this serves as an accountant for.
vaults: public(HashMap[address, bool])
# Mapping of strategy to bool if it has custom fees.
custom: public(HashMap[address, bool])
# Mapping strategy => custom Fee config
fees: public(HashMap[address, Fee])
# Default config to use unless a custom one is set.
default_config: public(Fee)

@external
def __init__(
    fee_manager: address, 
    default_management: uint16, 
    default_performance: uint16, 
    default_refund: uint16, 
    default_max: uint16
):
    assert default_management <= self._management_fee_threshold(), "exceeds management fee threshold"
    assert default_performance <= self._performance_fee_threshold(), "exceeds performance fee threshold"

    # Set the default fee config
    self.default_config = Fee({
        management_fee: default_management,
        performance_fee: default_performance,
        refund_ratio: default_refund,
        max_fee: default_max
    })

    log UpdateDefaultFeeConfig(self.default_config)
    
    self.fee_manager = fee_manager

@external
def report(strategy: address, gain: uint256, loss: uint256) -> (uint256, uint256):
    """ 
    """
    # Make sure this is a valid vault.
    assert self.vaults[msg.sender], "!authorized"

    # Retrieve the strategies params from the vault.
    strategy_params: StrategyParams = IVault(msg.sender).strategies(strategy)
    # Expected behavior is to use the default config.
    fee: Fee = self.default_config

    # Use custom fees if applicable.
    if self.custom[strategy]:
        fee = self.fees[strategy]

    total_fees: uint256 = 0
    total_refunds: uint256 = 0

    if fee.management_fee > 0:
        duration: uint256 = block.timestamp - strategy_params.last_report
        #management_fee
        total_fees = (
            strategy_params.current_debt
            * duration
            * convert(fee.management_fee, uint256)
            / MAX_BPS
            / SECS_PER_YEAR
        )

    if gain > 0:
        total_fees += (gain * convert(fee.performance_fee, uint256)) / MAX_BPS

    else:
        if fee.refund_ratio > 0:
            asset: address = IVault(msg.sender).asset()
            # Give back either all we have or based on refund ratio.
            total_refunds = min(loss * convert(fee.refund_ratio, uint256) / MAX_BPS, ERC20(asset).balanceOf(self))

            if total_refunds > 0:
                self.erc20_safe_approve(asset, msg.sender, total_refunds)
    
    # 0 Max fee means it is not enforced.
    if fee.max_fee > 0:
        # ensure fee does not exceed more than the max_fee %.
        total_fees = min(gain * convert(fee.max_fee, uint256) / MAX_BPS, total_fees)

    return (total_fees, total_refunds)

@internal
def erc20_safe_approve(token: address, spender: address, amount: uint256):
    # Used only to send tokens that are not the type managed by this Vault.
    # HACK: Used to handle non-compliant tokens like USDT
    response: Bytes[32] = raw_call(
        token,
        concat(
            method_id("approve(address,uint256)"),
            convert(spender, bytes32),
            convert(amount, bytes32),
        ),
        max_outsize=32,
    )
    if len(response) > 0:
        assert convert(response, bool), "approval failed!"


@external
def add_vault(vault: address):
    """
    @notice Add a new vault for this accountant to charge fee for.
    @dev This is not used to set any of the fees for the specific 
    vault or strategy. Each fee will be set seperatly. 
    @param vault The address of a vault to allow to use this accountant.
    """
    assert msg.sender == self.fee_manager, "not fee manager"
    assert not self.vaults[vault], "already added"

    self.vaults[vault] = True

    log VaultChanged(vault, ChangeType.ADDED)


@external
def remove_vault(vault: address):
    """
    @notice Removes a vault for this accountant to charge fee for.
    @param vault The address of a vault to allow to use this accountant.
    """
    assert msg.sender == self.fee_manager, "not fee manager"
    assert self.vaults[vault], "not added"

    self.vaults[vault] = False

    log VaultChanged(vault, ChangeType.REMOVED)


@external
def update_default_config(
    default_management: uint16, 
    default_performance: uint16, 
    default_refund: uint16, 
    default_max: uint16
):
    assert msg.sender == self.fee_manager, "not fee manager"
    assert default_management <= self._management_fee_threshold(), "exceeds management fee threshold"
    assert default_performance <= self._performance_fee_threshold(), "exceeds performance fee threshold"

    self.default_config = Fee({
        management_fee: default_management,
        performance_fee: default_performance,
        refund_ratio: default_refund,
        max_fee: default_max
    })

    log UpdateDefaultFeeConfig(self.default_config)

@external
def set_custom_config(
    strategy: address,
    custom_management: uint16, 
    custom_performance: uint16, 
    custom_refund: uint16, 
    custom_max: uint16
):
    assert msg.sender == self.fee_manager, "not fee manager"
    assert custom_management <= self._management_fee_threshold(), "exceeds management fee threshold"
    assert custom_performance <= self._performance_fee_threshold(), "exceeds performance fee threshold"

    # If this is the first custom fee set for this strategy.
    if not self.custom[strategy]:
        # Update the custom flag.
        self.custom[strategy] = True

    self.fees[strategy] = Fee({
        management_fee: custom_management,
        performance_fee: custom_performance,
        refund_ratio: custom_refund,
        max_fee: custom_max
    })

    log UpdateCustomFeeConfig(strategy, self.fees[strategy])

@external
def remove_custom_config(strategy: address):
    assert msg.sender == self.fee_manager, "not fee manager"
    assert self.custom[strategy], "No custom fees set"

    # Set custom bool flag back to false.
    self.custom[strategy] = False

    # Set all the strategies custom fees to 0.
    self.fees[strategy] = Fee({
        management_fee: 0,
        performance_fee: 0,
        refund_ratio: 0,
        max_fee: 0
    })

    # Emit relevant event.
    log UpdateCustomFeeConfig(strategy, self.fees[strategy])


@external
def withdraw_underlying(vault: address, amount: uint256) -> uint256:
    assert msg.sender == self.fee_manager, "not fee manager"
    return IVault(vault).redeem(amount, self, self)

@external
def distribute(token: address):
    assert msg.sender == self.fee_manager, "not fee manager"

    rewards: uint256 = ERC20(token).balanceOf(self)
    self._erc20_safe_transfer(token, msg.sender, rewards)

    log DistributeRewards(token, rewards)


@internal
def _erc20_safe_transfer(token: address, receiver: address, amount: uint256):
    # Used only to send tokens that are not the type managed by this Vault.
    # HACK: Used to handle non-compliant tokens like USDT
    response: Bytes[32] = raw_call(
        token,
        concat(
            method_id("transfer(address,uint256)"),
            convert(receiver, bytes32),
            convert(amount, bytes32),
        ),
        max_outsize=32,
    )
    if len(response) > 0:
        assert convert(response, bool), "Transfer failed!"


@external
def set_future_fee_manager(future_fee_manager: address):
    assert msg.sender == self.fee_manager, "not fee manager"
    assert future_fee_manager != empty(address), "ZERO ADDRESS"
    self.future_fee_manager = future_fee_manager

    log SetFutureFeeManager(future_fee_manager)


@external
def accept_fee_manager():
    assert msg.sender == self.future_fee_manager, "not future fee manager"
    self.fee_manager = self.future_fee_manager
    self.future_fee_manager = empty(address)

    log NewFeeManager(msg.sender)


@view
@external
def performance_fee_threshold() -> uint16:
    return self._performance_fee_threshold()


@view
@internal
def _performance_fee_threshold() -> uint16:
    return convert(MAX_BPS / 2, uint16)


@view
@external
def management_fee_threshold() -> uint16:
    return self._management_fee_threshold()


@view
@internal
def _management_fee_threshold() -> uint16:
    return 200