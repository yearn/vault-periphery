// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

/// @notice Holds the `management` role of a V3 strategy so that a
///  debt allocator can call both reports and change the profit unlock time.
contract StrategyManager is Governance {
    /// @notice Emitted when a new strategy is added to the manager.
    event StrategyAdded(address indexed strategy, address indexed owner);

    /// @notice Emitted when a strategy is removed.
    event StrategyRemoved(address indexed strategy, address indexed newManager);

    /// @notice Only the `_strategy` specific owner can call.
    modifier onlyStrategyOwner(address _strategy) {
        _checkStrategyOwner(_strategy);
        _;
    }

    /// @notice Strategy must be added and debt manager is calling.
    modifier onlyStrategyAndDebtManager(address _strategy) {
        _checkStrategyAndDebtManager(_strategy);
        _;
    }

    /// @notice Checks if the msg sender is the owner of the strategy.
    function _checkStrategyOwner(address _strategy) internal view virtual {
        require(strategyOwner[_strategy] == msg.sender, "!owner");
    }

    /// @notice Checks if the msg sender is the debt manager and the strategy is added.
    function _checkStrategyAndDebtManager(
        address _strategy
    ) internal view virtual {
        require(
            yieldManager == msg.sender &&
                strategyOwner[_strategy] != address(0),
            "!debt manager"
        );
    }

    /// @notice Debt manager contract that can call this manager.
    address public immutable yieldManager;

    /// @notice strategy address => struct with info.
    mapping(address => address) public strategyOwner;

    constructor(address _governance) Governance(_governance) {
        yieldManager = msg.sender;
    }

    /**
     * @notice Add a new strategy, using the current `management` as the owner.
     * @param _strategy The address of the strategy.
     */
    function manageNewStrategy(address _strategy) external {
        address currentManager = IStrategy(_strategy).management();
        manageNewStrategy(_strategy, currentManager);
    }

    /**
     * @notice Manage a new strategy, setting the debt manager and marking it as active.
     * @param _strategy The address of the strategy.
     * @param _owner The address in charge of the strategy now.
     */
    function manageNewStrategy(
        address _strategy,
        address _owner
    ) public onlyGovernance {
        require(
            _owner != address(0) &&
                _owner != address(this) &&
                _owner != _strategy,
            "bad address"
        );
        require(strategyOwner[_strategy] == address(0), "already active");

        // Accept management of the strategy.
        IStrategy(_strategy).acceptManagement();

        // Store the owner of the strategy.
        strategyOwner[_strategy] = _owner;

        emit StrategyAdded(_strategy, _owner);
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
        strategyOwner[_strategy] = _newOwner;
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

        delete strategyOwner[_strategy];

        IStrategy(_strategy).setPendingManagement(_newManager);

        emit StrategyRemoved(_strategy, _newManager);
    }

    /**
     * @notice Reports full profit for a strategy.
     * @param _strategy The address of the strategy.
     */
    function reportFullProfit(
        address _strategy
    ) external onlyStrategyAndDebtManager(_strategy) {
        // Get the current unlock rate.
        uint256 profitUnlock = IStrategy(_strategy).profitMaxUnlockTime();

        if (profitUnlock != 1) {
            // Set profit unlock to 0.
            IStrategy(_strategy).setProfitMaxUnlockTime(1);
        }

        // Report profits.
        IStrategy(_strategy).report();

        if (profitUnlock != 1) {
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
    ) public onlyStrategyOwner(_strategy) returns (bytes memory) {
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
