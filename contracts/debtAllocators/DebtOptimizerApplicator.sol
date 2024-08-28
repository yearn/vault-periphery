// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.18;

import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {IDebtAllocatorFactory} from "./DebtAllocator.sol";

interface IDebtAllocator {
    function setStrategyDebtRatio(
        address _strategy,
        uint256 _targetRatio
    ) external;
    function setStrategyDebtRatio(
        address _strategy,
        uint256 _targetRatio,
        uint256 _maxRatio
    ) external;
}

contract DebtOptimizerApplicator is Multicall {
    /// @notice An event emitted when a keeper is added or removed.
    event UpdateManager(address indexed manager, bool allowed);

    /// @notice struct for debt ratio changes
    struct StrategyDebtRatio {
        address strategy;
        uint256 targetRatio;
        uint256 maxRatio;
    }

    /// @notice Make sure the caller is governance.
    modifier onlyGovernance() {
        _isGovernance();
        _;
    }

    /// @notice Make sure the caller is governance or a manager.
    modifier onlyManagers() {
        _isManager();
        _;
    }

    /// @notice Check the Factories governance address.
    function _isGovernance() internal view virtual {
        require(
            msg.sender ==
                IDebtAllocatorFactory(debtAllocatorFactory).governance(),
            "!governance"
        );
    }

    /// @notice Check is either factories governance or local manager.
    function _isManager() internal view virtual {
        require(
            managers[msg.sender] ||
                msg.sender ==
                IDebtAllocatorFactory(debtAllocatorFactory).governance(),
            "!manager"
        );
    }

    /// @notice The address of the debt allocator factory to use for some role checks.
    address public immutable debtAllocatorFactory;

    /// @notice Mapping of addresses that are allowed to update debt ratios.
    mapping(address => bool) public managers;

    constructor(address _debtAllocatorFactory) {
        debtAllocatorFactory = _debtAllocatorFactory;
    }

    /**
     * @notice Set if a manager can update ratios.
     * @param _address The address to set mapping for.
     * @param _allowed If the address can call {update_debt}.
     */
    function setManager(
        address _address,
        bool _allowed
    ) external virtual onlyGovernance {
        managers[_address] = _allowed;

        emit UpdateManager(_address, _allowed);
    }

    function setStrategyDebtRatios(
        address _debtAllocator,
        StrategyDebtRatio[] calldata _strategyDebtRatios
    ) public onlyManagers {
        for (uint8 i; i < _strategyDebtRatios.length; ++i) {
            if (_strategyDebtRatios[i].maxRatio == 0) {
                IDebtAllocator(_debtAllocator).setStrategyDebtRatio(
                    _strategyDebtRatios[i].strategy,
                    _strategyDebtRatios[i].targetRatio
                );
            } else {
                IDebtAllocator(_debtAllocator).setStrategyDebtRatio(
                    _strategyDebtRatios[i].strategy,
                    _strategyDebtRatios[i].targetRatio,
                    _strategyDebtRatios[i].maxRatio
                );
            }
        }
    }
}
