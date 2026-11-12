// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {Accountant, ERC20, SafeERC20} from "../accountants/Accountant.sol";

interface IAuction {
    function kick(address _token) external returns (uint256);
}

contract Dumper is Governance {
    using SafeERC20 for ERC20;

    modifier onlyAllowed() {
        require(msg.sender == governance || allowed[msg.sender], "NOT ALLOWED");
        _;
    }

    Accountant public immutable accountant;

    address public immutable splitter;

    address public splitToken;

    address public auction;

    mapping(address => bool) public allowed;

    constructor(
        address _governance,
        address _accountant,
        address _splitter,
        address _splitToken
    ) Governance(_governance) {
        require(_accountant != address(0), "ZERO ADDRESS");
        require(_splitter != address(0), "ZERO ADDRESS");
        require(_splitToken != address(0), "ZERO ADDRESS");
        accountant = Accountant(_accountant);
        splitter = _splitter;
        splitToken = _splitToken;
    }

    // Send the split token to the Splitter contract.
    function distribute() external {
        ERC20(splitToken).safeTransfer(
            splitter,
            ERC20(splitToken).balanceOf(address(this)) - 1
        );
    }

    function dumpToken(address _token) external onlyAllowed {
        _dumpToken(_token);
    }

    function dumpTokens(address[] calldata _tokens) external onlyAllowed {
        for (uint256 i; i < _tokens.length; ++i) {
            _dumpToken(_tokens[i]);
        }
    }

    function _dumpToken(address _token) internal {
        uint256 accountantBalance = ERC20(_token).balanceOf(
            address(accountant)
        );
        if (accountantBalance > 0) {
            accountant.distribute(_token);
        }
        ERC20(_token).safeTransfer(
            auction,
            ERC20(_token).balanceOf(address(this)) - 1
        );
        IAuction(auction).kick(_token);
    }

    // Claim the fees from the accountant
    function claimToken(address _token) external onlyAllowed {
        accountant.distribute(_token);
    }

    function claimTokens(address[] calldata _tokens) external onlyAllowed {
        for (uint256 i; i < _tokens.length; ++i) {
            accountant.distribute(_tokens[i]);
        }
    }

    function claimToken(address _token, uint256 _amount) external onlyAllowed {
        accountant.distribute(_token, _amount);
    }

    function sweep(address _token) external onlyGovernance {
        ERC20(_token).safeTransfer(
            governance,
            ERC20(_token).balanceOf(address(this))
        );
    }

    function setSplitToken(address _splitToken) external onlyGovernance {
        require(_splitToken != address(0), "ZERO ADDRESS");
        splitToken = _splitToken;
    }

    function setAuction(address _auction) external onlyGovernance {
        auction = _auction;
    }

    function setAllowed(
        address _person,
        bool _allowed
    ) external onlyGovernance {
        allowed[_person] = _allowed;
    }
}
