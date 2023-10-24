# @version 0.3.7

"""
@title Generic Accountant
@license GNU AGPLv3
@author yearn.finance
@notice
    This generic accountant is meant to serve as the accountant role
    for a Yearn V3 Vault. 
    https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy

    It is designed to be able to be added to any number of vaults with any 
    underlying tokens. There is a default fee config that will be used for 
    any strategy that reports through a vault that has been added to this
    accountant. But also gives the ability for the feeManager to choose 
    custom values for any value for any given strategy they want to.

    Funds received from the vaults can either be distributed to a specified
    feeRecipient or redeemed for the underlying asset and held within this
    contract until distributed.
"""
from vyper.interfaces import ERC20

### INTERFACES ###
struct StrategyParams:
    activation: uint256
    last_report: uint256
    current_debt: uint256
    max_debt: uint256

interface IVault:
    def asset() -> address: view
    def strategies(strategy: address) -> StrategyParams: view
    def withdraw(amount: uint256, receiver: address, owner: address, maxLoss: uint256) -> uint256: nonpayable

### EVENTS ###

event VaultChanged:
    vault: indexed(address)
    change: ChangeType

event UpdateDefaultFeeConfig:
    defaultFeeConfig: Fee

event SetFutureFeeManager:
    futureFeeManager: indexed(address)

event NewFeeManager:
    feeManager: indexed(address)

event UpdateFeeRecipient:
    oldFeeRecipient: indexed(address)
    newFeeRecipient: indexed(address)

event UpdateCustomFeeConfig:
    vault: indexed(address)
    strategy: indexed(address)
    customConfig: Fee

event RemovedCustomFeeConfig:
    vault: indexed(address)
    strategy: indexed(address)

event UpdateMaxLoss:
    maxLoss: uint256

event DistributeRewards:
    token: indexed(address)
    rewards: uint256

### ENUMS ###

enum ChangeType:
    ADDED
    REMOVED

### STRUCTS ###

# Struct that holds all needed amounts to charge fees
# and issue refunds. All amounts are expressed in Basis points.
# i.e. 10_000 == 100%.
struct Fee:
    # Annual management fee to charge on strategy debt.
    managementFee: uint16
    # Performance fee to charge on reported gain.
    performanceFee: uint16
    # Ratio of reported loss to attempt to refund.
    refundRatio: uint16
    # Max percent of the reported gain that the accountant can take.
    # A maxFee of 0 will mean none is enforced.
    maxFee: uint16


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

PERFORMANCE_FEE_THRESHOLD: constant(uint16) = 5_000

MANAGEMENT_FEE_THRESHOLD: constant(uint16) = 200

### STORAGE ###

# Address in charge of the accountant.
feeManager: public(address)
# Address to become the fee manager.
futureFeeManager: public(address)
# Address to distribute the accumulated fees to.
feeRecipient: public(address)
# Max loss variable to use on withdraws.
maxLoss: public(uint256)

# Mapping of vaults that this serves as an accountant for.
vaults: public(HashMap[address, bool])
# Default config to use unless a custom one is set.
defaultConfig: public(Fee)
# Mapping vault => strategy => custom Fee config
customConfig: public(HashMap[address, HashMap[address, Fee]])
# Mapping vault => strategy => flag to use a custom config.
custom: public(HashMap[address, HashMap[address, bool]])

@external
def __init__(
    fee_manager: address, 
    fee_recipient: address,
    default_management: uint16, 
    default_performance: uint16, 
    default_refund: uint16, 
    default_maxFee: uint16
):
    """
    @notice Initialize the accountant and default fee config.
    @param fee_manager Address to be in charge of this accountant.
    @param fee_recipient Address to receive fees.
    @param default_management Default annual management fee to charge.
    @param default_performance Default performance fee to charge.
    @param default_refund Default refund ratio to give back on losses.
    @param default_maxFee Default max fee to allow as a percent of gain.
    """
    assert fee_manager != empty(address), "ZERO ADDRESS"
    assert fee_recipient != empty(address), "ZERO ADDRESS"
    assert default_management <= MANAGEMENT_FEE_THRESHOLD, "exceeds management fee threshold"
    assert default_performance <= PERFORMANCE_FEE_THRESHOLD, "exceeds performance fee threshold"

    # Set initial addresses
    self.feeManager = fee_manager
    self.feeRecipient = fee_recipient

    # Set the default fee config
    self.defaultConfig = Fee({
        managementFee: default_management,
        performanceFee: default_performance,
        refundRatio: default_refund,
        maxFee: default_maxFee
    })

    log UpdateDefaultFeeConfig(self.defaultConfig)


@external
def report(strategy: address, gain: uint256, loss: uint256) -> (uint256, uint256):
    """ 
    @notice To be called by a vault during the process_report in which the accountant
        will charge fees based on the gain or loss the strategy is reporting.
    @dev Can only be called by a vault that has been added to this accountant.
        Will default to the defaultConfig for all amounts unless a custom config
        has been set for a specific strategy.
    @param strategy The strategy that is reporting.
    @param gain The profit the strategy is reporting if any.
    @param loss The loss the strategy is reporting if any.
    """
    # Make sure this is a valid vault.
    assert self.vaults[msg.sender], "!authorized"

    # Declare the config to use
    fee: Fee = empty(Fee)

    # Check if it there is a custom config to use.
    if self.custom[msg.sender][strategy]:
        fee = self.customConfig[msg.sender][strategy]
    else:
        # Otherwise use the default.
        fee = self.defaultConfig

    total_fees: uint256 = 0
    total_refunds: uint256 = 0

    # Charge management fees no matter gain or loss.
    if fee.managementFee > 0:
        # Retrieve the strategies params from the vault.
        strategy_params: StrategyParams = IVault(msg.sender).strategies(strategy)
        # Time since last harvest.
        duration: uint256 = block.timestamp - strategy_params.last_report
        # managementFee is an annual amount, so charge based on the time passed.
        total_fees = (
            strategy_params.current_debt
            * duration
            * convert(fee.managementFee, uint256)
            / MAX_BPS
            / SECS_PER_YEAR
        )

    # Only charge performance fees if there is a gain.
    if gain > 0:
        total_fees += (gain * convert(fee.performanceFee, uint256)) / MAX_BPS
    else:
        # Means we should have a loss.
        if fee.refundRatio > 0:
            # Cache the underlying asset the vault uses.
            asset: address = IVault(msg.sender).asset()
            # Give back either all we have or based on refund ratio.
            total_refunds = min(loss * convert(fee.refundRatio, uint256) / MAX_BPS, ERC20(asset).balanceOf(self))

            if total_refunds > 0:
                # Approve the vault to pull the underlying asset.
                self.erc20_safe_approve(asset, msg.sender, total_refunds)
    
    # 0 Max fee means it is not enforced.
    if fee.maxFee > 0:
        # Ensure fee does not exceed the maxFee %.
        total_fees = min(gain * convert(fee.maxFee, uint256) / MAX_BPS, total_fees)

    return (total_fees, total_refunds)


@internal
def erc20_safe_approve(token: address, spender: address, amount: uint256):
    # Used only to approve tokens that are not the type managed by this vault.
    # Used to handle non-compliant tokens like USDT
    assert ERC20(token).approve(spender, amount, default_return_value=True), "approval failed"

@internal
def _erc20_safe_transfer(token: address, receiver: address, amount: uint256):
    # Used only to send tokens that are not the type managed by this vault.
    assert ERC20(token).transfer(receiver, amount, default_return_value=True), "transfer failed"


@external
def addVault(vault: address):
    """
    @notice Add a new vault for this accountant to charge fees for.
    @dev This is not used to set any of the fees for the specific 
    vault or strategy. Each fee will be set separately. 
    @param vault The address of a vault to allow to use this accountant.
    """
    assert msg.sender == self.feeManager, "!fee manager"
    assert not self.vaults[vault], "already added"

    self.vaults[vault] = True

    log VaultChanged(vault, ChangeType.ADDED)


@external
def removeVault(vault: address):
    """
    @notice Removes a vault for this accountant to charge fee for.
    @param vault The address of a vault to allow to use this accountant.
    """
    assert msg.sender == self.feeManager, "!fee manager"
    assert self.vaults[vault], "not added"

    self.vaults[vault] = False

    log VaultChanged(vault, ChangeType.REMOVED)


@external
def updateDefaultConfig(
    default_management: uint16, 
    default_performance: uint16, 
    default_refund: uint16, 
    default_maxFee: uint16
):
    """
    @notice Update the default config used for all strategies.
    @param default_management Default annual management fee to charge.
    @param default_performance Default performance fee to charge.
    @param default_refund Default refund ratio to give back on losses.
    @param default_maxFee Default max fee to allow as a percent of gain.
    """
    assert msg.sender == self.feeManager, "!fee manager"
    assert default_management <= MANAGEMENT_FEE_THRESHOLD, "exceeds management fee threshold"
    assert default_performance <= PERFORMANCE_FEE_THRESHOLD, "exceeds performance fee threshold"

    self.defaultConfig = Fee({
        managementFee: default_management,
        performanceFee: default_performance,
        refundRatio: default_refund,
        maxFee: default_maxFee
    })

    log UpdateDefaultFeeConfig(self.defaultConfig)


@external
def setCustomConfig(
    vault: address,
    strategy: address,
    custom_management: uint16, 
    custom_performance: uint16, 
    custom_refund: uint16, 
    custom_maxFee: uint16
):
    """
    @notice Used to set a custom fee amounts for a specific strategy.
        In a specific vault.
    @dev Setting this will cause the default config to be overridden.
    @param vault The vault the strategy is hooked up to.
    @param strategy The strategy to customize.
    @param custom_management Custom annual management fee to charge.
    @param custom_performance Custom performance fee to charge.
    @param custom_refund Custom refund ratio to give back on losses.
    @param custom_maxFee Custom max fee to allow as a percent of gain.
    """
    assert msg.sender == self.feeManager, "!fee manager"
    assert self.vaults[vault], "vault not added"
    assert custom_management <= MANAGEMENT_FEE_THRESHOLD, "exceeds management fee threshold"
    assert custom_performance <= PERFORMANCE_FEE_THRESHOLD, "exceeds performance fee threshold"

    # Set this strategies custom config.
    self.customConfig[vault][strategy] = Fee({
        managementFee: custom_management,
        performanceFee: custom_performance,
        refundRatio: custom_refund,
        maxFee: custom_maxFee
    })

    # Make sure flag is declared as True.
    self.custom[vault][strategy] = True

    log UpdateCustomFeeConfig(vault, strategy, self.customConfig[vault][strategy])


@external
def removeCustomConfig(vault: address, strategy: address):
    """
    @notice Removes a previously set custom config for a strategy.
    @param strategy The strategy to remove custom setting for.
    """
    assert msg.sender == self.feeManager, "!fee manager"
    assert self.custom[vault][strategy], "No custom fees set"

    # Set all the strategies custom fees to 0.
    self.customConfig[vault][strategy] = empty(Fee)
    # Turn off the flag.
    self.custom[vault][strategy] = False

    # Emit relevant event.
    log RemovedCustomFeeConfig(vault, strategy)

@external
def setMaxLoss(maxLoss: uint256):
    """
    @notice Set the max loss parameter to be used on withdraws.
    @param maxLoss Amount in basis points.
    """
    assert msg.sender == self.feeManager, "!fee manager"
    assert maxLoss <= MAX_BPS, "higher than 100%"

    self.maxLoss = maxLoss

    log UpdateMaxLoss(maxLoss)

@external
def withdrawUnderlying(vault: address, amount: uint256):
    """
    @notice Can be used by the fee manager to simply withdraw the underlying
        asset from a vault it charges fees for.
    @dev Refunds are payed in the underlying but fees are charged in the vaults
        token. So management may want to fee some funds to allow for refunds to 
        work across all vaults of the same underlying.
    @param vault The vault to redeem from.
    @param amount The amount in the underlying to withdraw.
    """
    assert msg.sender == self.feeManager, "!fee manager"
    IVault(vault).withdraw(amount, self, self, self.maxLoss)


@external
def distribute(token: address) -> uint256:
    """
    @notice used to withdraw accumulated fees to the designated recipient.
    @dev This can be used to withdraw the vault tokens or underlying tokens
        that had previously been withdrawn.
    @param token The token to distribute.
    @return The amount of token distributed.
    """
    assert msg.sender == self.feeManager, "!fee manager"

    rewards: uint256 = ERC20(token).balanceOf(self)
    self._erc20_safe_transfer(token, self.feeRecipient, rewards)

    log DistributeRewards(token, rewards)
    return rewards


@external
def setFutureFeeManager(futureFeeManager: address):
    """
    @notice Step 1 of 2 to set a new feeManager.
    @dev The address is set to futureFeeManager and will need to
        call accept_feeManager in order to update the actual feeManager.
    @param futureFeeManager Address to set to futureFeeManager.
    """
    assert msg.sender == self.feeManager, "!fee manager"
    assert futureFeeManager != empty(address), "ZERO ADDRESS"
    self.futureFeeManager = futureFeeManager

    log SetFutureFeeManager(futureFeeManager)


@external
def acceptFeeManager():
    """
    @notice to be called by the futureFeeManager to accept the role change.
    """
    assert msg.sender == self.futureFeeManager, "not future fee manager"
    self.feeManager = self.futureFeeManager
    self.futureFeeManager = empty(address)

    log NewFeeManager(msg.sender)


@external
def setFeeRecipient(newFeeRecipient: address):
    """
    @notice Set a new address to receive distributed rewards.
    @param newFeeRecipient Address to receive distributed fees.
    """
    assert msg.sender == self.feeManager, "!fee manager"
    assert newFeeRecipient != empty(address), "ZERO ADDRESS"
    oldFeeRecipient: address = self.feeRecipient
    self.feeRecipient = newFeeRecipient

    log UpdateFeeRecipient(oldFeeRecipient, newFeeRecipient)


@view
@external
def performanceFeeThreshold() -> uint16:
    """
    @notice External function to get the max a performance fee can be.
    @return Max performance fee the accountant can charge.
    """
    return PERFORMANCE_FEE_THRESHOLD


@view
@external
def managementFeeThreshold() -> uint16:
    """
    @notice External function to get the max a management fee can be.
    @return Max management fee the accountant can charge.
    """
    return MANAGEMENT_FEE_THRESHOLD
