// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract MockERC20 is ERC20Mock {
    constructor(
        string memory _name,
        string memory _symbol,
        address _initialUser,
        uint256 _initialAmount
    ) ERC20Mock(_name, _symbol, _initialUser, _initialAmount) {}
}
