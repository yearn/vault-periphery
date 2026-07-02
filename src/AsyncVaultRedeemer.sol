// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Governance} from "@periphery/utils/Governance.sol";

/// @title AsyncVaultRedeemer
/// @notice Must serve as the `withdraw_limit_module` for the vault.
///    User calls `requestRedeem` which will transfer the shares to the contract.
///    Then call `processRedeem` to redeem the shares once the cooldown period has passed.
contract AsyncVaultRedeemer is Governance {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for ERC20;

    event RedeemRequested(
        address indexed user,
        uint256 indexed shares,
        uint256 unlockTimestamp
    );
    event MaxLossUpdated(uint256 newMaxLoss);

    struct RedeemRequest {
        uint192 shares;
        uint64 requestedAt;
    }

    /// @notice The vault that the shares are being redeemed from.
    IVault public immutable vault;

    uint256 public maxLoss;

    /// @notice The amount of shares that are pending redemption.
    uint256 public pendingRedemptions;

    /// @notice The withdraw requests of users.
    mapping(address => RedeemRequest) public redeemRequests;

    EnumerableSet.AddressSet _requesters;

    constructor(address _governance, address _vault) Governance(_governance) {
        vault = IVault(_vault);
        maxLoss = 1;
    }

    function available_withdraw_limit(
        address owner,
        uint256,
        address[] memory
    ) public view returns (uint256) {
        if (owner == address(this)) {
            // TODO: Replicate vault logic. Or just use totalIdle?
            return type(uint256).max;
        } else {
            return 0;
        }
    }

    // NOTE: Should this be allowed?
    function processRedeem(uint256 _shares) public {
        RedeemRequest memory request = redeemRequests[msg.sender];

        require(request.shares >= _shares, "not enough shares");

        redeemRequests[msg.sender].shares -= uint192(_shares);
        pendingRedemptions -= _shares;

        vault.redeem(_shares, msg.sender, address(this), maxLoss);
    }

    // NOTE: Atomic redemtion if liquidity is available.
    // Dont need this if we dont use this is the withdraw limit module
    function requestAndProcessRedeem(uint256 _shares) external {
        requestRedeem(_shares);
        processRedeem(_shares);
    }

    function processRequests(
        address[] calldata _users
    ) external onlyGovernance {
        for (uint256 i = 0; i < _users.length; i++) {
            _processRequest(_users[i], redeemRequests[_users[i]].shares);
        }
    }

    function processRequests(
        address[] calldata _users,
        uint256[] calldata _shares
    ) external onlyGovernance {
        require(_users.length == _shares.length, "length mismatch");

        for (uint256 i = 0; i < _users.length; i++) {
            _processRequest(_users[i], _shares[i]);
        }
    }

    function processAllRequests() external onlyGovernance {
        uint256 length = _requesters.length();
        for (uint256 i = 0; i < length; i++) {
            address user = _requesters.at(i);
            _processRequest(user, redeemRequests[user].shares);
        }
    }

    function _processRequest(address _user, uint256 _shares) internal {
        require(_shares > 0, "zero shares");
        require(_requesters.contains(_user), "not found");

        RedeemRequest memory request = redeemRequests[_user];
        require(request.shares >= _shares, "not enough shares");

        redeemRequests[_user].shares -= uint192(_shares);
        pendingRedemptions -= _shares;

        if (request.shares == _shares) {
            _requesters.remove(_user);
        }

        vault.redeem(_shares, _user, address(this), maxLoss);
    }

    /**
     * @notice Requests a redemption of shares from the vault.
     * @dev This will override time of existing redeem request.
     * @param _shares The amount of shares to redeem.
     */
    function requestRedeem(uint256 _shares) public {
        _shares = Math.min(_shares, vault.balanceOf(msg.sender));
        require(_shares > 0, "zero shares");

        RedeemRequest memory request = redeemRequests[msg.sender];

        vault.transferFrom(msg.sender, address(this), _shares);

        redeemRequests[msg.sender] = RedeemRequest({
            shares: request.shares + uint192(_shares), // Add to existing request
            requestedAt: uint64(block.timestamp)
        });

        _requesters.add(msg.sender);

        pendingRedemptions += _shares;

        emit RedeemRequested(msg.sender, _shares, block.timestamp);
    }

    function setMaxLoss(uint256 _maxLoss) external onlyGovernance {
        require(_maxLoss < 10_000, "too high");
        maxLoss = _maxLoss;

        emit MaxLossUpdated(_maxLoss);
    }
}
