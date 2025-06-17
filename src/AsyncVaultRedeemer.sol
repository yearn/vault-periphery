// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Governance} from "@periphery/utils/Governance.sol";

/// @title AsyncVaultRedeemer
/// @notice Must serve as the `withdraw_limit_module` for the vault.
///    User calls `requestRedeem` which will transfer the shares to the contract.
///    Then call `processRedeem` to redeem the shares once the cooldown period has passed.
contract AsyncVaultRedeemer is Governance {
    using SafeERC20 for ERC20;

    event RedeemRequested(
        address indexed user,
        uint256 indexed shares,
        uint256 unlockTimestamp
    );
    event WithdrawWindowUpdated(uint256 newWithdrawWindow);
    event WithdrawCooldownUpdated(uint256 newWithdrawCooldown);

    struct RedeemRequest {
        uint256 shares;
        uint256 unlockTimestamp;
    }

    /// @notice The vault that the shares are being redeemed from.
    IVault public immutable vault;

    /// @notice The cooldown period after a withdraw request before the user can withdraw.
    uint256 public withdrawCooldown;

    /// @notice The window of time after a withdraw request has cooled down that the withdraw can be processed.
    /// If this window passes without the user calling `withdraw`, the user will need to recall `requestWithdraw`.
    uint256 public withdrawWindow;

    /// @notice The amount of shares that are pending redemption.
    uint256 public pendingRedemptions;

    /// @notice The withdraw requests of users.
    mapping(address => RedeemRequest) public redeemRequests;

    constructor(
        address _governance,
        address _vault,
        uint256 _withdrawCooldown,
        uint256 _withdrawWindow
    ) Governance(_governance) {
        vault = IVault(_vault);

        require(_withdrawCooldown < 365 days, "too long");
        require(_withdrawWindow > 1 days, "too short");

        withdrawCooldown = _withdrawCooldown;
        emit WithdrawCooldownUpdated(_withdrawCooldown);

        withdrawWindow = _withdrawWindow;
        emit WithdrawWindowUpdated(_withdrawWindow);
    }

    function available_withdraw_limit(
        address owner,
        uint256,
        address[] memory
    ) public view returns (uint256) {
        if (owner == address(this)) {
            return type(uint256).max;
        } else {
            return 0;
        }
    }

    function processRedeem(uint256 _shares) external {
        RedeemRequest memory request = redeemRequests[msg.sender];

        require(request.unlockTimestamp < block.timestamp, "not ready");
        require(
            request.unlockTimestamp + withdrawWindow > block.timestamp,
            "window passed"
        );
        require(request.shares >= _shares, "not enough shares");

        redeemRequests[msg.sender].shares -= _shares;
        pendingRedemptions -= _shares;

        vault.redeem(_shares, msg.sender, address(this));
    }

    /**
     * @notice Requests a redemption of shares from the strategy.
     * @dev This will override any existing redeem request.
     * @param _shares The amount of shares to redeem.
     */
    function requestRedeem(uint256 _shares) external {
        _shares = Math.min(_shares, vault.balanceOf(msg.sender));

        // Can use 0 to requeue the request
        if (_shares > 0) {
            vault.transferFrom(msg.sender, address(this), _shares);
        }

        redeemRequests[msg.sender] = RedeemRequest({
            shares: redeemRequests[msg.sender].shares + _shares,
            unlockTimestamp: block.timestamp + withdrawCooldown
        });

        pendingRedemptions += _shares;

        emit RedeemRequested(
            msg.sender,
            _shares,
            block.timestamp + withdrawCooldown
        );
    }

    /**
     * @dev Set the withdraw cooldown.
     * @param _withdrawCooldown The withdraw cooldown.
     */
    function setWithdrawCooldown(
        uint256 _withdrawCooldown
    ) external onlyGovernance {
        require(_withdrawCooldown < 365 days, "too long");
        withdrawCooldown = _withdrawCooldown;
        emit WithdrawCooldownUpdated(_withdrawCooldown);
    }

    /**
     * @dev Set the withdraw window.
     * @param _withdrawWindow The withdraw window.
     */
    function setWithdrawWindow(
        uint256 _withdrawWindow
    ) external onlyGovernance {
        require(_withdrawWindow > 1 days, "too short");
        withdrawWindow = _withdrawWindow;
        emit WithdrawWindowUpdated(_withdrawWindow);
    }
}
