// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Governance2Step} from "@periphery/utils/Governance2Step.sol";
import {HealthCheckAccountant} from "../accountants/HealthCheckAccountant.sol";

contract FeeSplitter is Governance2Step {

    struct Vault {
        address shareHolder;
        uint256 currentDeposits;
        uint256 lastDeposit;
    }
    struct Partner {
        address govenator;
        address feeRecipient;
        mapping(address => Vault) vault;
    }

    uint256 internal constant WAD = 1e18;
    
    mapping(bytes32 => Partner) public partners; // Use uint and start at 1 to keep track of number?

    address public accountant;

    constructor(address _governance, address _accountant) Governance2Step(_governance){
        accountant = _accountant;
    }

    function deposit(address _vault, bytes32 _partnerId, uint256 _amount) external virtual returns (uint256) {
        // Accrue reward balance

        // Deposit in vault and send to vault holder.

        // Track the amount of shares now and update tracked balance
    }

    function redeem(address _vault, bytes32 _partnerId, uint256 _amount, address _receiver, uint256 maxLoss) external virtual returns (uint256) {
        // Accrue reward balance
        
        // Withdraw on behalf of holder

        // Lower amount accounting for the time till now
    }

    function addPartner() external virtual onlyGovernance {
        // Add partner logic
    }

    function addPartnerVaults(bytes32 partnerId, address[] memory vaults, address[] memory holders) external virtual onlyGovernance {
        // check vault is eligible through the accountant?
        // Add each vault to the partner mapping
    }


    function removePartnerVaults(bytes32 partnerId, address[] memory vaults) external virtual onlyGovernance {
        // Remove each vault to the partner mapping
    }

    function removePartner() external onlyGovernance {
        // Remove partner logic
    }

    function setAccountant(address _newAccountant) external virtual onlyGovernance {
        accountant = _newAccountant;
    }

    function updateInfo() external {
        // Update info logic
    }

    function claimFees(bytes32 partnerId, address[] memory vaults) external virtual returns (uint256[] memory claimed) {
        Partner storage partner = partners[partnerId];
        require(partner.govenator != address(0), "!partner");
        require(msg.sender == partner.govenator || msg.sender == governance, "!allowed");

        claimed = new uint256[](vaults.length);
        address vault;
        address holder;
        address recipient = partner.feeRecipient;
        for (uint256 i = 0; i < vaults.length; i++) {
            vault = vaults[i];
            holder = partner.vault[vault].shareHolder;
            require(holder != address(0), "vault not added");

            HealthCheckAccountant(accountant).distribute(vault);
            claimed[i] = _claimFees(vault, holder, recipient);
        }

        return claimed;
    }

    /**
    * TODO:
     Track claimed balance and timestamp to not repay
     Track fee share balance so the percent isn't dependant on order claimed
     Use a time weighted balance of holder so cant deposit right before the fee claim
     */
    function _claimFees(address vault, address holder, address recipient) internal virtual returns (uint256 feesClaimed) {
        // % of tvl in 1e18 scale
        uint256 percent = IVault(vault).balanceOf(holder) * WAD / IVault(vault).totalAssets();

        // total fees owned
        feesClaimed = IVault(vault).balanceOf(address(this)) * percent / WAD;

        IVault(vault).transfer(recipient, feesClaimed);
    }

}