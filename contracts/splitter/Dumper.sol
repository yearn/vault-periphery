// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {Accountant, ERC20, SafeERC20} from "../accountants/Accountant.sol";

contract Dumper is Governance {
    using SafeERC20 for ERC20;

    address public immutable accountant;

    address public tf;

    constructor(
        address _governance,
        address _accountant,
        address _tf
    ) Governance(_governance) {
        accountant = _accountant;
        tf = _tf;
    }

    function setTf(address _tf) external onlyGovernance {
        tf = _tf;
    }

    function distribute(address _token) external onlyGovernance {
        Accountant(accountant).distribute(_token);
        uint256 balance = ERC20(_token).balanceOf(address(this));
        ERC20(tf).safeTransfer(tf, balance);
    }

    function distribute(
        address _token,
        uint256 _amount
    ) external onlyGovernance {
        Accountant(accountant).distribute(_token, _amount);
        ERC20(_token).safeTransfer(tf, _amount);
    }
}
