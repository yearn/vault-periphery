// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {MockTokenizedStrategy} from "@yearn-vaults/test/mocks/ERC4626/MockTokenizedStrategy.sol";

contract MockTokenized is MockTokenizedStrategy {
    uint256 public apr;
    uint256 public loss;

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
}
