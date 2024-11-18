// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {ISplitter} from "../interfaces/ISplitter.sol";
import {Governance} from "@periphery/utils/Governance.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IAuction {
    function kick(address _token) external returns (uint256);
}

contract Dumper is Governance {
    using SafeERC20 for ERC20;

    modifier onlyAllowed() {
        require(msg.sender == governance || allowed[msg.sender], "NOT ALLOWED");
        _;
    }

    ISplitter public immutable feeRecipient;

    address public splitToken;

    mapping(address => bool) public allowed;

    constructor(
        address _governance,
        address _feeRecipient,
        address _splitToken
    ) Governance(_governance) {
        require(_feeRecipient != address(0), "ZERO ADDRESS");
        require(_splitToken != address(0), "ZERO ADDRESS");
        feeRecipient = ISplitter(_feeRecipient);
        splitToken = _splitToken;
    }

    // Send the split token to the Splitter contract.
    function distribute() external {
        feeRecipient.distributeToken(splitToken);
    }

    function dumpToken(address _token) external onlyAllowed {
        _dumpToken(_token);
    }

    function dumpTokens(address[] calldata _tokens) external onlyAllowed {
        for (uint256 i = 0; i < _tokens.length; i++) {
            _dumpToken(_tokens[i]);
        }
    }

    function _dumpToken(address _token) internal {
        feeRecipient.fundAuction(_token);
        IAuction(feeRecipient.auction()).kick(_token);
    }

    function unwrapVault(address _vault) external onlyAllowed {
        feeRecipient.unwrapVault(_vault);
    }

    function unwrapVaults(address[] calldata _vaults) external onlyAllowed {
        feeRecipient.unwrapVaults(_vaults);
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

    function setAllowed(
        address _person,
        bool _allowed
    ) external onlyGovernance {
        allowed[_person] = _allowed;
    }
}
