// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

/// @notice Holds the `management` role of a V3 strategy so that a
///  debt allocator can call both reports and change the profit unlock time.
contract StrategyManager is Governance {
    /// @notice Emitted when a new strategy is added to the manager.
    event StrategyAdded(
        address indexed strategy,
        address indexed owner,
        address indexed debtManager
    );

    /// @notice Emitted when a strategy is removed.
    event StrategyRemoved(address indexed strategy, address indexed newManager);

    /// @notice holds info for a strategy that is managed.
    struct StrategyInfo {
        bool active;
        address owner;
        address debtManager;
    }

    /// @notice Only the `_strategy` specific owner can call.
    modifier onlyStrategyOwner(address _strategy) {
        _checkStrategyOwner(_strategy);
        _;
    }

    /// @notice Only the `_strategy` owner of its debt manager can call.
    modifier onlyStrategyOwnerOrDebtManager(address _strategy) {
        _checkStrategyDebtManager(_strategy);
        _;
    }

    /// @notice Checks if the msg sender is the owner of the strategy.
    function _checkStrategyOwner(address _strategy) internal view virtual {
        require(strategyInfo[_strategy].owner == msg.sender, "!owner");
    }

    /// @notice Checks if the msg sender is the debt manager or the strategy owner.
    function _checkStrategyDebtManager(
        address _strategy
    ) internal view virtual {
        require(
            strategyInfo[_strategy].debtManager == msg.sender ||
                strategyInfo[_strategy].owner == msg.sender,
            "!debt manager"
        );
    }

    /// @notice strategy address => struct with info.
    mapping(address => StrategyInfo) public strategyInfo;

    /// @notice function selector => bool if a debt manager can call that.
    mapping(bytes4 => bool) public allowedSelectors;

    /**
     * @notice Add any of the allowed selectors for a debt manager to call
     *   to the mapping.
     */
    constructor(
        address _governance,
        bytes4[] memory _allowedSelectors
    ) Governance(_governance) {
        for (uint256 i = 0; i < _allowedSelectors.length; ++i) {
            allowedSelectors[_allowedSelectors[i]] = true;
        }
    }

    /**
     * @notice Add a new strategy, using the current `management` as the owner.
     * @param _strategy The address of the strategy.
     * @param _debtManager The address of the debt manager.
     */
    function manageNewStrategy(
        address _strategy,
        address _debtManager
    ) external {
        address currentManager = IStrategy(_strategy).management();
        manageNewStrategy(_strategy, _debtManager, currentManager);
    }

    /**
     * @notice Manage a new strategy, setting the debt manager and marking it as active.
     * @param _strategy The address of the strategy.
     * @param _debtManager The address of the debt manager.
     * @param _owner The address in charge of the strategy now.
     */
    function manageNewStrategy(
        address _strategy,
        address _debtManager,
        address _owner
    ) public onlyGovernance {
        require(!strategyInfo[_strategy].active, "already active");

        // Accept management of the strategy.
        IStrategy(_strategy).acceptManagement();

        // Store the owner of the strategy.
        strategyInfo[_strategy] = StrategyInfo({
            active: true,
            owner: _owner,
            debtManager: _debtManager
        });

        emit StrategyAdded(_strategy, _owner, _debtManager);
    }

    /**
     * @notice Updates the owner of a strategy.
     * @param _strategy The address of the strategy.
     * @param _newOwner The address of the new owner.
     */
    function updateStrategyOwner(
        address _strategy,
        address _newOwner
    ) external onlyStrategyOwner(_strategy) {
        require(
            _newOwner != address(0) &&
                _newOwner != address(this) &&
                _newOwner != _strategy,
            "bad address"
        );
        strategyInfo[_strategy].owner = _newOwner;
    }

    /**
     * @notice Updates the debt manager of a strategy.
     * @param _strategy The address of the strategy.
     * @param _newDebtManager The address of the new owner.
     */
    function updateDebtManager(
        address _strategy,
        address _newDebtManager
    ) external onlyStrategyOwner(_strategy) {
        strategyInfo[_strategy].debtManager = _newDebtManager;
    }

    /**
     * @notice Removes the management of a strategy, transferring it to the `owner`.
     * @param _strategy The address of the strategy.
     */
    function removeManagement(address _strategy) external {
        removeManagement(_strategy, msg.sender);
    }

    /**
     * @notice Removes the management of a strategy, transferring it to a new manager.
     * @param _strategy The address of the strategy.
     * @param _newManager The address of the new manager.
     */
    function removeManagement(
        address _strategy,
        address _newManager
    ) public onlyStrategyOwner(_strategy) {
        require(
            _newManager != address(0) &&
                _newManager != address(this) &&
                _newManager != _strategy,
            "bad address"
        );

        delete strategyInfo[_strategy];

        IStrategy(_strategy).setPendingManagement(_newManager);

        emit StrategyRemoved(_strategy, _newManager);
    }

    /**
     * @notice Reports full profit for a strategy.
     * @param _strategy The address of the strategy.
     */
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

    /**
     * @notice Forwards multiple calls to a strategy.
     * @param _strategy The address of the strategy.
     * @param _calldataArray An array of calldata for each call.
     * @return _returnData An array of return data from each call.
     */
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

    /**
     * @notice Forwards a single call to a strategy.
     * @param _strategy The address of the strategy.
     * @param _calldata The calldata for the call.
     * @return _returnData The return data from the call.
     */
    function forwardCall(
        address _strategy,
        bytes memory _calldata
    ) public returns (bytes memory) {
        bytes4 selector;

        assembly {
            // Copy the first 4 bytes of the memory array to the selector variable
            selector := mload(add(_calldata, 32))
        }

        if (allowedSelectors[selector]) {
            _checkStrategyDebtManager(_strategy);
        } else {
            _checkStrategyOwner(_strategy);
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
