// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Governance} from "@periphery/utils/Governance.sol";

contract InitGov {
    address public constant multisig =
        0x33333333D5eFb92f19a5F94a43456b3cec2797AE;

    address public constant EOA = 0xD7392bcc3D3611adF1793fDdaAAB4770772AC35A;

    modifier onlyGov() {
        _checkGov();
        _;
    }

    // Default to 0x33 ms as gov if deployed. But backs up to an EOA if not.
    function _checkGov() internal view {
        if (multiSig.code.length != 0) {
            require(msg.sender == multisig, "!gov");
        } else {
            require(msg.sender == eoa, "!gov");
        }
    }

    function transferGovernance(
        address _contract,
        address _newOwner
    ) external onlyGov {
        Governance(_contract).transferGovernance(_newOwner);
    }
}
