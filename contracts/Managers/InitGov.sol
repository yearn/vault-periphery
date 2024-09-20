// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";

contract InitGov {
    modifier onlyGov() {
        _checkGov();
        _;
    }

    address public constant multisig =
        0x33333333D5eFb92f19a5F94a43456b3cec2797AE;

    address public constant SIGNER_ONE =
        0xD7392bcc3D3611adF1793fDdaAAB4770772AC35A;
    address public constant SIGNER_TWO =
        0xa05c4256ff0dd38697e63D48dF146e6e2FE7fe4A;
    address public constant SIGNER_THREE =
        0x305af52AC31d3F9Daa1EC6231bA7b36Bb40f42f4;
    address public constant SIGNER_FOUR =
        0x80f751EdcB3012d5AF5530AFE97d5dC6EE176Bc0;
    address public constant SIGNER_FIVE =
        0x6d2b80BA79871281Be7F70b079996a052B8D62F4;
    address public constant SIGNER_SIX =
        0x623d4A04e19328244924D1dee48252987C02fC0a;

    uint256 public constant THRESHOLD = 3;

    mapping(address => bool) public isSigner;

    mapping(bytes32 => uint256) public numberSigned;

    mapping(address => mapping(bytes32 => bool)) public signed;

    constructor() {
        isSigner[SIGNER_ONE] = true;
        isSigner[SIGNER_TWO] = true;
        isSigner[SIGNER_THREE] = true;
        isSigner[SIGNER_FOUR] = true;
        isSigner[SIGNER_FIVE] = true;
        isSigner[SIGNER_SIX] = true;
    }

    // Default to 0x33 ms as gov if deployed. But backs up to an EOA if not.
    function _checkGov() internal view {
        require(msg.sender == multisig, "!gov");
    }

    function signTxn(address _contract, address _newGov) external {
        require(isSigner[msg.sender], "!signer");
        bytes32 id = getTxnId(_contract, _newGov);
        require(!signed[msg.sender][id], "already signer");

        signed[msg.sender][id] = true;
        numberSigned[id] += 1;

        if (numberSigned[id] == THRESHOLD)
            _transferGovernance(_contract, _newGov);
    }

    function transferGovernance(
        address _contract,
        address _newOwner
    ) external onlyGov {
        _transferGovernance(_contract, _newOwner);
    }

    function _transferGovernance(
        address _contract,
        address _newOwner
    ) internal {
        Governance(_contract).transferGovernance(_newOwner);
    }

    function getTxnId(
        address _contract,
        address _newGov
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_contract, _newGov));
    }
}
