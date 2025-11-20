// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IZKC} from "../interfaces/IZKC.sol";
import {Supply} from "../libraries/Supply.sol";

/// @title CirculatingZKC - Circulating Supply Calculator for ZKC
/// @notice Contract to track and calculate the circulating supply of ZKC tokens
/// @dev Uses an admin-controlled unlocked value plus claimed tokens to calculate circulating supply
contract CirculatingZKC is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @notice Admin role identifier
    bytes32 public immutable ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// @notice Reference to the ZKC token contract
    IZKC public zkc;

    /// @notice Amount of tokens considered unlocked and in circulation
    uint256 public unlocked;

    /// @notice Amount of tokens considered locked and not in circulation
    uint256 public locked;

    /// @notice Emitted when the unlocked value is updated
    /// @param oldValue The previous unlocked value
    /// @param newValue The new unlocked value
    event UnlockedValueUpdated(uint256 oldValue, uint256 newValue);

    /// @notice Emitted when the locked value is updated
    /// @param oldValue The previous locked value
    /// @param newValue The new locked value
    event LockedValueUpdated(uint256 oldValue, uint256 newValue);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the CirculatingZKC contract
    /// @param _zkc Address of the ZKC token contract
    /// @param _initialUnlocked Initial value for the unlocked tokens
    /// @param _admin Address that will be granted the admin role
    function initialize(address _zkc, uint256 _initialUnlocked, address _admin) public initializer {
        require(_zkc != address(0), "ZKC address cannot be zero");
        require(_admin != address(0), "Admin address cannot be zero");

        __AccessControl_init();
        __UUPSUpgradeable_init();

        zkc = IZKC(_zkc);
        unlocked = _initialUnlocked;
        locked = Supply.INITIAL_SUPPLY - _initialUnlocked;
        _grantRole(ADMIN_ROLE, _admin);
    }

    /// @notice Calculate the current circulating supply
    /// @dev Formula: claimedTotalSupply - locked
    /// @return The current circulating supply of ZKC tokens
    function circulatingSupply() public view returns (uint256) {
        uint256 claimedTotal = zkc.claimedTotalSupply();
        return claimedTotal - locked;
    }

    /// @notice Update the unlocked value
    /// @dev Only callable by accounts with ADMIN_ROLE
    /// @dev Also updates locked to keep them in sync: locked = INITIAL_SUPPLY - unlocked
    /// @param _newUnlocked The new value for unlocked tokens
    function updateUnlockedValue(uint256 _newUnlocked) external onlyRole(ADMIN_ROLE) {
        uint256 oldValue = unlocked;
        unlocked = _newUnlocked;
        locked = Supply.INITIAL_SUPPLY - _newUnlocked;
        emit UnlockedValueUpdated(oldValue, _newUnlocked);
    }

    /// @notice Update the locked value
    /// @dev Only callable by accounts with ADMIN_ROLE
    /// @dev Also updates unlocked to keep them in sync: unlocked = INITIAL_SUPPLY - locked
    /// @param _newLocked The new value for locked tokens
    function updateLockedValue(uint256 _newLocked) external onlyRole(ADMIN_ROLE) {
        uint256 oldValue = locked;
        locked = _newLocked;
        unlocked = Supply.INITIAL_SUPPLY - _newLocked;
        emit LockedValueUpdated(oldValue, _newLocked);
    }

    /// @notice Authorize contract upgrades (UUPS pattern)
    /// @dev Only accounts with ADMIN_ROLE can authorize upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
