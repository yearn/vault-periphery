// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

// Allow for an array of calls

contract StrategyManager {
    struct StrategyInfo {
        bool active;
        address owner;
        address debtManager;
    }

    modifier onlyStrategyOwner(address _strategy) {
        _checkStrategyManager(_strategy);
        _;
    }

    modifier onlyStrategyOwnerOrDebtManager(address _strategy) {
        _checkStrategyDebtManager(_strategy);
        _;
    }

    /// @notice Checks if the msg sender is the governance.
    function _checkStrategyManager(address _strategy) internal view virtual {
        require(strategyInfo[_strategy].owner == msg.sender, "!governance");
    }

    function _checkStrategyDebtManager(
        address _strategy
    ) internal view virtual {
        require(
            strategyInfo[_strategy].debtManager == msg.sender ||
                strategyInfo[_strategy].owner == msg.sender,
            "!debt manager"
        );
    }

    mapping(address => StrategyInfo) public strategyInfo;

    mapping(bytes4 => bool) public allowedSelectors;

    constructor(bytes4[] memory _allowedSelectors) {
        for (uint256 i = 0; i < _allowedSelectors.length; ++i) {
            allowedSelectors[_allowedSelectors[i]];
        }
    }

    function manageNewStrategy(
        address _strategy,
        address _debtManager
    ) external {
        require(!strategyInfo[_strategy].active, "already active");
        // Cache the current strategy management.
        address currentManager = IStrategy(_strategy).management();

        // Accept management of the strategy.
        IStrategy(_strategy).acceptManagement();

        // Store the owner of the strategy.
        strategyInfo[_strategy] = StrategyInfo({
            active: true,
            owner: currentManager,
            debtManager: _debtManager
        });
    }

    function updateStrategyOwner(
        address _strategy,
        address _newOwner
    ) external onlyStrategyOwner(_strategy) {
        require(_newOwner != address(0), "ZERO ADDRESS");
        strategyInfo[_strategy].owner = _newOwner;
    }

    // This gets rid of the benefits of two step transfers.
    function removeManagement(
        address _strategy,
        address _newManager
    ) external onlyStrategyOwner(_strategy) {
        require(strategyInfo[_strategy].active, "not active");

        delete strategyInfo[_strategy];

        IStrategy(_strategy).setPendingManagement(_newManager);
    }

    function reportFullProfit(
        address _strategy
    ) external onlyStrategyOwnerOrDebtManager(_strategy) {
        // Get the current unlock rate.
        uint256 profitUnlock = IStrategy(_strategy).profitMaxUnlockTime();

        if (profitUnlock != 0) {
            // Set profit unlock to 0.
            IStrategy(_strategy).setProfitMaxUnlockTime(0);
        }

        // Report profits.
        IStrategy(_strategy).report();

        if (profitUnlock != 0) {
            // Set profit unlock back to original.
            IStrategy(_strategy).setProfitMaxUnlockTime(profitUnlock);
        }
    }

    function forwardCalls(
        address _strategy,
        bytes[] memory _calldataArray
    ) external returns (bytes[] memory _returnData) {
        uint256 _length = _calldataArray.length;
        _returnData = new bytes[](_length);
        for (uint256 i = 0; i < _length; ++i) {
            _returnData[i] = forwardCall(_strategy, _calldataArray[i]);
        }
    }

    function forwardCall(
        address _strategy,
        bytes memory _calldata
    ) public returns (bytes memory) {
        bytes4 selector;

        assembly {
            // Copy the first 4 bytes of the memory array to the result variable
            selector := mload(add(_calldata, 32))
        }

        if (allowedSelectors[selector]) {
            _checkStrategyDebtManager(_strategy);
        } else {
            _checkStrategyManager(_strategy);
        }

        (bool success, bytes memory result) = _strategy.call(_calldata);

        // If the call reverted. Return the error.
        if (!success) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        // Return the result.
        return result;
    }
}
