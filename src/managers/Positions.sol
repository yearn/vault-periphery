// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

contract Positions {
    /// @notice Emitted when a new address is set for a position.
    event UpdatePositionHolder(
        bytes32 indexed position,
        address indexed newAddress
    );

    /// @notice Emitted when a new set of roles is set for a position
    event UpdatePositionRoles(bytes32 indexed position, uint256 newRoles);

    /// @notice Position struct
    struct Position {
        address holder;
        uint96 roles;
    }

    /// @notice Only allow position holder to call.
    modifier onlyPositionHolder(bytes32 _positionId) {
        _isPositionHolder(_positionId);
        _;
    }

    /// @notice Check if the msg sender is specified position holder.
    function _isPositionHolder(bytes32 _positionId) internal view virtual {
        require(msg.sender == getPositionHolder(_positionId), "!allowed");
    }

    /// @notice Mapping of position ID to position information.
    mapping(bytes32 => Position) internal _positions;

    /**
     * @notice Setter function for updating a positions holder.
     */
    function _setPositionHolder(
        bytes32 _position,
        address _newHolder
    ) internal virtual {
        _positions[_position].holder = _newHolder;

        emit UpdatePositionHolder(_position, _newHolder);
    }

    /**
     * @notice Setter function for updating a positions roles.
     */
    function _setPositionRoles(
        bytes32 _position,
        uint256 _newRoles
    ) internal virtual {
        _positions[_position].roles = uint96(_newRoles);

        emit UpdatePositionRoles(_position, _newRoles);
    }

    /**
     * @notice Get the address and roles given to a specific position.
     * @param _positionId The position identifier.
     * @return The address that holds that position.
     * @return The roles given to the specified position.
     */
    function getPosition(
        bytes32 _positionId
    ) public view virtual returns (address, uint256) {
        Position memory _position = _positions[_positionId];
        return (_position.holder, uint256(_position.roles));
    }

    /**
     * @notice Get the current address assigned to a specific position.
     * @param _positionId The position identifier.
     * @return The current address assigned to the specified position.
     */
    function getPositionHolder(
        bytes32 _positionId
    ) public view virtual returns (address) {
        return _positions[_positionId].holder;
    }

    /**
     * @notice Get the current roles given to a specific position ID.
     * @param _positionId The position identifier.
     * @return The current roles given to the specified position ID.
     */
    function getPositionRoles(
        bytes32 _positionId
    ) public view virtual returns (uint256) {
        return uint256(_positions[_positionId].roles);
    }
}
