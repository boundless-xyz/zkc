// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IZKC} from "../interfaces/IZKC.sol";
import {Supply} from "../libraries/Supply.sol";

/// @title Supply Calculator for ZKC tokens
/// @notice Contract computes various supply metrics of ZKC tokens, intended to be used by frontend apps/exchanges
contract SupplyCalculator is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @notice Admin role identifier
    bytes32 public immutable ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// @notice Reference to the ZKC token contract
    IZKC public zkc;

    /// @notice Amount of tokens considered unlocked and in circulation
    uint256 public unlocked;

    /// @notice Emitted when the unlocked value is updated
    /// @param oldValue The previous unlocked value
    /// @param newValue The new unlocked value
    event UnlockedValueUpdated(uint256 oldValue, uint256 newValue);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the SupplyCalculator contract
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
        _grantRole(ADMIN_ROLE, _admin);
    }

    /// @notice Calculate the current circulating supply
    /// @dev Formula: unlocked + (zkc.claimedTotalSupply() - zkc.INITIAL_SUPPLY())
    /// @dev Essentially, unlocked tokens from the initial mint + claimed rewards from PoVW and staking rewards
    /// @return The current circulating supply of ZKC tokens
    function circulatingSupply() public view returns (uint256) {
        uint256 claimedTotal = zkc.claimedTotalSupply();
        uint256 initialSupply = Supply.INITIAL_SUPPLY;

        // Calculate the claimed rewards from PoVW and staking rewards
        uint256 claimedRewards = claimedTotal - initialSupply;

        return unlocked + claimedRewards;
    }

    /// @notice Calculate the current circulating supply rounded to the nearest whole token (18dp representation)
    /// @dev Returns value in wei (18 decimals) but rounded such that when converted to whole tokens it's rounded
    /// @return The current circulating supply rounded to nearest whole token in 18dp format
    function circulatingSupplyRounded() public view returns (uint256) {
        uint256 supply = circulatingSupply();
        return _roundTo18dp(supply);
    }

    /// @notice Calculate the current circulating supply as a rounded whole number
    /// @dev Returns the value in regular representation (divided by 10^18) rounded to nearest whole token
    /// @return The current circulating supply as a whole number
    function circulatingSupplyAmountRounded() public view returns (uint256) {
        uint256 supply = circulatingSupply();
        return _roundToWholeTokens(supply);
    }

    /// @notice Get the total supply
    /// @dev This represents the theoretical total supply of ZKC tokens based on the current epoch
    /// @return The total supply of ZKC tokens
    function totalSupply() public view returns (uint256) {
        return IERC20(address(zkc)).totalSupply();
    }

    /// @notice Get the total supply rounded to the nearest whole token (18dp representation)
    /// @dev Returns value in wei (18 decimals) but rounded such that when converted to whole tokens it's rounded
    /// @dev Uses the theoretical total supply based on current epoch
    /// @return The total supply rounded to nearest whole token in 18dp format
    function totalSupplyRounded() public view returns (uint256) {
        uint256 supply = IERC20(address(zkc)).totalSupply();
        return _roundTo18dp(supply);
    }

    /// @notice Get the total supply as a rounded whole number
    /// @dev Returns the value in regular representation (divided by 10^18) rounded to nearest whole token
    /// @dev Uses the theoretical total supply based on current epoch
    /// @return The total supply as a whole number
    function totalSupplyAmountRounded() public view returns (uint256) {
        uint256 supply = IERC20(address(zkc)).totalSupply();
        return _roundToWholeTokens(supply);
    }

    /// @notice Get the total claimed supply
    /// @dev This represents the initial supply that was minted and allocated to initial minters,
    ///      as well as tokens that have been claimed (and thus minted) via PoVW or Staking rewards.
    /// @return The total amount of tokens that have been claimed
    function claimedTotalSupply() public view returns (uint256) {
        return zkc.claimedTotalSupply();
    }

    /// @notice Get the claimed total supply rounded to the nearest whole token (18dp representation)
    /// @dev Returns value in wei (18 decimals) but rounded such that when converted to whole tokens it's rounded
    /// @dev Uses the actual claimed/minted supply
    /// @return The claimed total supply rounded to nearest whole token in 18dp format
    function claimedTotalSupplyRounded() public view returns (uint256) {
        uint256 supply = zkc.claimedTotalSupply();
        return _roundTo18dp(supply);
    }

    /// @notice Get the claimed total supply as a rounded whole number
    /// @dev Returns the value in regular representation (divided by 10^18) rounded to nearest whole token
    /// @dev Uses the actual claimed/minted supply
    /// @return The claimed total supply as a whole number
    function claimedTotalSupplyAmountRounded() public view returns (uint256) {
        uint256 supply = zkc.claimedTotalSupply();
        return _roundToWholeTokens(supply);
    }

    /// @notice Round a value to the nearest whole token (18dp representation)
    /// @dev Rounds to nearest 1e18, so when divided by 1e18 it gives a whole number
    /// @param value The value to round
    /// @return The rounded value in 18dp format
    function _roundTo18dp(uint256 value) private pure returns (uint256) {
        uint256 remainder = value % 1e18;
        if (remainder >= 5e17) {
            // Round up
            return value - remainder + 1e18;
        } else {
            // Round down
            return value - remainder;
        }
    }

    /// @notice Round a value to the nearest whole token and return as a whole number
    /// @dev Divides by 1e18 with rounding
    /// @param value The value to round
    /// @return The rounded value as a whole number
    function _roundToWholeTokens(uint256 value) private pure returns (uint256) {
        uint256 remainder = value % 1e18;
        if (remainder >= 5e17) {
            // Round up
            return (value / 1e18) + 1;
        } else {
            // Round down
            return value / 1e18;
        }
    }

    /// @notice Update the unlocked value
    /// @dev Only callable by accounts with ADMIN_ROLE
    /// @param _newUnlocked The new value for unlocked tokens
    function updateUnlockedValue(uint256 _newUnlocked) external onlyRole(ADMIN_ROLE) {
        uint256 oldValue = unlocked;
        unlocked = _newUnlocked;
        emit UnlockedValueUpdated(oldValue, _newUnlocked);
    }

    /// @notice Authorize contract upgrades (UUPS pattern)
    /// @dev Only accounts with ADMIN_ROLE can authorize upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
