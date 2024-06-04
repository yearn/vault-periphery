// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {Accountant, ERC20, SafeERC20} from "../accountants/Accountant.sol";

contract Dumper is TradeFactorySwapper, Governance {
    using SafeERC20 for ERC20;

    address public immutable accountant;

    address public immutable splitter;

    address public splitToken;

    constructor(
        address _governance,
        address _accountant,
        address _splitter,
        address _tf,
        address _splitToken
    ) Governance(_governance) {
        require(_accountant != address(0), "ZERO ADDRESS");
        require(_splitter != address(0), "ZERO ADDRESS");
        require(_splitToken != address(0), "ZERO ADDRESS");
        accountant = _accountant;
        splitter = _splitter;
        _setTradeFactory(_tf, _splitToken);
        splitToken = _splitToken;
    }

    function setTradeFactory(address _tf) external onlyGovernance {
        _setTradeFactory(_tf, splitToken);
    }

    function addToken(address _tokenFrom) external onlyGovernance {
        _addToken(_tokenFrom, splitToken);
    }

    function addTokens(address[] calldata _tokens) external onlyGovernance {
        address _splitToken = splitToken;
        for (uint256 i; i < _tokens.length; ++i) {
            _addToken(_tokens[i], _splitToken);
        }
    }

    function removeTokens(address[] calldata _tokens) external onlyGovernance {
        address _splitToken = splitToken;
        for (uint256 i; i < _tokens.length; ++i) {
            _removeToken(_tokens[i], _splitToken);
        }
    }

    function setSplitToken(address _splitToken) external onlyGovernance {
        require(_splitToken != address(0), "ZERO ADDRESS");
        // Set to same Trade Factory address but new split token
        _setTradeFactory(tradeFactory(), _splitToken);
        splitToken = _splitToken;
    }

    function distribute() external {
        ERC20(splitToken).safeTransfer(
            splitter,
            ERC20(splitToken).balanceOf(address(this))
        );
    }

    function _claimRewards() internal override {
        address[] memory localRewardTokens = rewardTokens();
        for (uint256 i; i < localRewardTokens.length; ++i) {
            Accountant(accountant).distribute(localRewardTokens[i]);
        }
    }

    function claim(address _token) external onlyGovernance {
        Accountant(accountant).distribute(_token);
    }

    function claim(address _token, uint256 _amount) external onlyGovernance {
        Accountant(accountant).distribute(_token, _amount);
    }
}