// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {TokenizedStrategy, ERC20} from "@tokenized-strategy/TokenizedStrategy.sol";

contract MockTokenizedStrategy is TokenizedStrategy {
    uint256 public minDebt;
    uint256 public maxDebt = type(uint256).max;

    // Private variables and functions used in this mock.
    bytes32 public constant BASE_STRATEGY_STORAGE =
        bytes32(uint256(keccak256("yearn.base.strategy.storage")) - 1);

    function strategyStorage() internal pure returns (StrategyData storage S) {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = BASE_STRATEGY_STORAGE;
        assembly {
            S.slot := slot
        }
    }

    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper
    ) {
        // Cache storage pointer
        StrategyData storage S = strategyStorage();

        // Set the strategy's underlying asset
        S.asset = ERC20(_asset);
        // Set the Strategy Tokens name.
        S.name = _name;
        // Set decimals based off the `asset`.
        S.decimals = ERC20(_asset).decimals();

        // Set last report to this block.
        S.lastReport = uint128(block.timestamp);

        // Set the default management address. Can't be 0.
        require(_management != address(0), "ZERO ADDRESS");
        S.management = _management;
        S.performanceFeeRecipient = _management;
        // Set the keeper address
        S.keeper = _keeper;
    }

    function setMinDebt(uint256 _minDebt) external {
        minDebt = _minDebt;
    }

    function setMaxDebt(uint256 _maxDebt) external {
        maxDebt = _maxDebt;
    }

    function availableDepositLimit(
        address
    ) public view virtual returns (uint256) {
        uint256 _totalAssets = strategyStorage().totalIdle;
        uint256 _maxDebt = maxDebt;
        return _maxDebt > _totalAssets ? _maxDebt - _totalAssets : 0;
    }

    function availableWithdrawLimit(
        address /*_owner*/
    ) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function deployFunds(uint256 _amount) external virtual {}

    function freeFunds(uint256 _amount) external virtual {}

    function harvestAndReport() external virtual returns (uint256) {
        return strategyStorage().asset.balanceOf(address(this));
    }
}

contract MockTokenized is MockTokenizedStrategy {
    uint256 public apr;
    uint256 public loss;
    uint256 public limit;

    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        uint256 _apr
    ) MockTokenizedStrategy(_asset, _name, _management, _keeper) {
        apr = _apr;
    }

    function aprAfterDebtChange(
        address,
        int256
    ) external view returns (uint256) {
        return apr;
    }

    function setApr(uint256 _apr) external {
        apr = _apr;
    }

    function realizeLoss(uint256 _amount) external {
        strategyStorage().asset.transfer(msg.sender, _amount);
        strategyStorage().totalIdle -= _amount;
        strategyStorage().totalDebt += _amount;
    }

    function tendThis(uint256) external {}

    function availableWithdrawLimit(
        address _owner
    ) public view virtual override returns (uint256) {
        if (limit != 0) {
            uint256 _totalAssets = strategyStorage().totalIdle;
            return _totalAssets > limit ? _totalAssets - limit : 0;
        } else {
            return super.availableWithdrawLimit(_owner);
        }
    }

    function setLimit(uint256 _limit) external {
        limit = _limit;
    }
}
