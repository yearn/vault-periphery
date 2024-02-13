// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";
import {HealthCheckAccountant} from "../accountants/HealthCheckAccountant.sol";

contract FeeSplitter is Governance2Step {
    using SafeERC20 for ERC20;

    struct Vault {
        address shareHolder;
        uint256 currentDeposits;
        uint256 lastUpdate;
    }
    struct Partner {
        address govenator;
        address feeRecipient;
        mapping(address => Vault) vault;
    }

    modifier updateFees(address _vault, bytes32 _partnerId) {
        _updateFees(_vault, _partnerId);
        _;
    }

    function _updateFees(address _vault, bytes32 _partnerId) internal {
        Vault memory vault = partners[_partnerId].vault[_vault];
        require(vault.shareHolder != address(0), "not active");
        uint256 balance = Math.min(
            vault.currentDeposits,
            IVault(_vault).balanceOf(address(vault.shareHolder))
        );
        uint256 time = block.timestamp - vault.lastUpdate;
        earned[_vault][_partnerId] +=
            (vaultRate[_vault] * balance * time) /
            WAD;
        partners[_partnerId].vault[_vault].lastUpdate = block.timestamp;
    }

    uint256 internal constant WAD = 1e18;

    mapping(bytes32 => Partner) public partners; // Use uint and start at 1 to keep track of number?

    mapping(address => uint256) public vaultRate;

    // TODO Combine into one mapping
    mapping(address => mapping(bytes32 => uint256)) public earned;
    mapping(address => mapping(bytes32 => uint256)) public paid;

    address public accountant;

    constructor(
        address _governance,
        address _accountant
    ) Governance2Step(_governance) {
        accountant = _accountant;
    }

    function deposit(
        address _vault,
        bytes32 _partnerId,
        uint256 _amount
    ) external virtual updateFees(_vault, _partnerId) returns (uint256 shares) {
        // Deposit in vault and send to vault holder.
        address asset = IVault(_vault).asset();

        ERC20(asset).safeTransferFrom(msg.sender, address(this), _amount);

        _checkAllowance(_vault, asset);

        shares = IVault(_vault).deposit(
            _amount,
            partners[_partnerId].vault[_vault].shareHolder
        );

        // Track the amount of shares now and update tracked balance
        partners[_partnerId].vault[_vault].currentDeposits += _amount;
    }

    function redeem(
        address _vault,
        bytes32 _partnerId,
        uint256 _amount,
        address _receiver,
        uint256 maxLoss
    )
        external
        virtual
        updateFees(_vault, _partnerId)
        returns (uint256 withdrawn)
    {
        // Withdraw on behalf of holder
        withdrawn = IVault(_vault).redeem(
            _amount,
            msg.sender,
            _receiver,
            maxLoss
        );

        // Lower amount accounting for the time till now
        uint256 deposits = partners[_partnerId].vault[_vault].currentDeposits;
        partners[_partnerId].vault[_vault].currentDeposits = deposits >
            withdrawn
            ? deposits - withdrawn
            : 0;
    }

    function addPartner() external virtual onlyGovernance {
        // Add partner logic
    }

    function addPartnerVaults(
        bytes32 partnerId,
        address[] calldata vaults,
        address[] calldata holders
    ) external virtual onlyGovernance {
        // check vault is eligible through the accountant?
        // Add each vault to the partner mapping
    }

    function removePartnerVaults(
        bytes32 partnerId,
        address[] calldata vaults
    ) external virtual onlyGovernance {
        // Remove each vault to the partner mapping
    }

    function removePartner() external onlyGovernance {
        // Remove partner logic
    }

    function setAccountant(
        address _newAccountant
    ) external virtual onlyGovernance {
        accountant = _newAccountant;
    }

    function updateInfo() external {
        // Update info logic
    }

    function claimFees(
        bytes32 _partnerId,
        address[] calldata vaults
    ) external virtual returns (uint256[] memory claimed) {
        Partner storage partner = partners[_partnerId];
        require(partner.govenator != address(0), "!partner");
        require(
            msg.sender == partner.govenator || msg.sender == governance,
            "!allowed"
        );

        claimed = new uint256[](vaults.length);
        address vault;
        address recipient = partner.feeRecipient;
        for (uint256 i = 0; i < vaults.length; i++) {
            vault = vaults[i];

            _updateFees(vault, _partnerId);

            uint256 toPay = earned[vault][_partnerId] - paid[vault][_partnerId];

            _claimFees(vault, recipient, toPay);

            claimed[i] = toPay;
            paid[vault][_partnerId] += toPay;
        }

        return claimed;
    }

    /**
    * TODO:
     Track claimed balance and timestamp to not repay
     Track fee share balance so the percent isn't dependant on order claimed
     Use a time weighted balance of holder so cant deposit right before the fee claim
     */
    function _claimFees(
        address vault,
        address recipient,
        uint256 toClaim
    ) internal virtual {
        if (IVault(vault).balanceOf(address(this)) < toClaim) {
            HealthCheckAccountant(accountant).distribute(vault);
        }

        IVault(vault).transfer(recipient, toClaim);
    }

    /**
     * @dev Internal safe function to make sure the contract you want to
     * interact with has enough allowance to pull the desired tokens.
     *
     * @param _contract The address of the contract that will move the token.
     * @param _token The ERC-20 token that will be getting spent.
     */
    function _checkAllowance(
        address _contract,
        address _token
    ) internal virtual {
        // Yearn vaults don't lower allowance if set to max uint
        if (
            ERC20(_token).allowance(address(this), _contract) !=
            type(uint256).max
        ) {
            ERC20(_token).safeApprove(_contract, type(uint256).max);
        }
    }
}
