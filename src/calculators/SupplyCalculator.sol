// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IZKC} from "../interfaces/IZKC.sol";
import {Supply} from "../libraries/Supply.sol";
import {UnlockSchedule} from "../libraries/UnlockSchedule.sol";

/// @title Supply Calculator for ZKC tokens
/// @notice Contract computes various supply metrics of ZKC tokens, intended to be used by frontend apps/exchanges
contract SupplyCalculator is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @notice Admin role identifier
    bytes32 public immutable ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// @notice Reference to the ZKC token contract
    IZKC public zkc;

    /// @custom:oz-renamed-from unlocked
    uint256 private _deprecatedUnlocked;

    /// @custom:oz-renamed-from locked
    uint256 private _deprecatedLocked;

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
        _deprecatedUnlocked = _initialUnlocked;
        _deprecatedLocked = Supply.INITIAL_SUPPLY - _initialUnlocked;
        _grantRole(ADMIN_ROLE, _admin);
    }

    /// @notice Initialize V2: Set locked value directly
    /// @param newLocked Initial value for the locked tokens
    /// @dev Sets locked to specified value and unlocked to INITIAL_SUPPLY - locked
    function initializeV2(uint256 newLocked) public reinitializer(2) {
        require(newLocked <= Supply.INITIAL_SUPPLY, "Locked cannot exceed initial supply");

        _deprecatedLocked = newLocked;
        _deprecatedUnlocked = Supply.INITIAL_SUPPLY - newLocked;
    }

    /// @notice Genesis allocation unlocked at the current block timestamp
    /// @return Cumulative unlocked ZKC from the initial 1B supply
    function unlocked() public view returns (uint256) {
        return UnlockSchedule.unlockedAt(block.timestamp);
    }

    /// @notice Genesis allocation locked at the current block timestamp
    /// @return ZKC from the initial 1B supply that remains locked
    function locked() public view returns (uint256) {
        return UnlockSchedule.lockedAt(block.timestamp);
    }

    /// @notice Calculate the current circulating supply
    /// @dev Formula: claimedTotalSupply - locked
    /// @return The current circulating supply of ZKC tokens
    function circulatingSupply() public view returns (uint256) {
        return zkc.claimedTotalSupply() - locked();
    }

    /// @notice Calculate the current circulating supply rounded to the nearest whole token (18dp representation)
    /// @dev Returns value in wei (18 decimals) but rounded such that when converted to whole tokens it's rounded
    /// @return The current circulating supply rounded to nearest whole token in 18dp format
    function circulatingSupplyRounded() public view returns (uint256) {
        return _roundTo18dp(circulatingSupply());
    }

    /// @notice Calculate the current circulating supply as a rounded whole number
    /// @dev Returns the value in regular representation (divided by 10^18) rounded to nearest whole token
    /// @return The current circulating supply as a whole number
    function circulatingSupplyAmountRounded() public view returns (uint256) {
        return _roundToWholeTokens(circulatingSupply());
    }

    /// @notice Genesis allocation unlocked at a specific timestamp
    /// @param timestamp Unix timestamp to query
    /// @return Cumulative unlocked ZKC from the initial 1B supply
    function unlockedAtTimestamp(uint256 timestamp) public pure returns (uint256) {
        return UnlockSchedule.unlockedAt(timestamp);
    }

    /// @notice Genesis allocation locked at a specific timestamp
    /// @param timestamp Unix timestamp to query
    /// @return ZKC from the initial 1B supply that remains locked
    function lockedAtTimestamp(uint256 timestamp) public pure returns (uint256) {
        return UnlockSchedule.lockedAt(timestamp);
    }

    /// @notice Get the total supply
    /// @dev This represents the theoretical total supply of ZKC tokens based on the current epoch
    /// @return The total supply of ZKC tokens
    function totalSupply() public view returns (uint256) {
        return IERC20(address(zkc)).totalSupply();
    }

    /// @notice Theoretical total supply at a specific timestamp
    /// @dev Uses ZKC epoch math. Returns INITIAL_SUPPLY before epochs start or before `timestamp` reaches epoch 0
    /// @param timestamp Unix timestamp to query
    /// @return Theoretical total ZKC supply at the start of the epoch containing `timestamp`
    function totalSupplyAtTimestamp(uint256 timestamp) public view returns (uint256) {
        uint256 epoch0Start = zkc.epoch0StartTime();
        if (epoch0Start == 0 || epoch0Start == type(uint256).max || timestamp < epoch0Start) {
            return Supply.INITIAL_SUPPLY;
        }
        uint256 epoch = (timestamp - epoch0Start) / Supply.EPOCH_DURATION;
        return zkc.getSupplyAtEpochStart(epoch);
    }

    /// @notice Get the total supply rounded to the nearest whole token (18dp representation)
    /// @dev Returns value in wei (18 decimals) but rounded such that when converted to whole tokens it's rounded
    /// @dev Uses the theoretical total supply based on current epoch
    /// @return The total supply rounded to nearest whole token in 18dp format
    function totalSupplyRounded() public view returns (uint256) {
        return _roundTo18dp(totalSupply());
    }

    /// @notice Theoretical total supply at `timestamp`, rounded to nearest whole token (18dp representation)
    /// @param timestamp Unix timestamp to query
    /// @return Total supply rounded to nearest whole token in 18dp format
    function totalSupplyRoundedAtTimestamp(uint256 timestamp) public view returns (uint256) {
        return _roundTo18dp(totalSupplyAtTimestamp(timestamp));
    }

    /// @notice Get the total supply as a rounded whole number
    /// @dev Returns the value in regular representation (divided by 10^18) rounded to nearest whole token
    /// @dev Uses the theoretical total supply based on current epoch
    /// @return The total supply as a whole number
    function totalSupplyAmountRounded() public view returns (uint256) {
        return _roundToWholeTokens(totalSupply());
    }

    /// @notice Theoretical total supply at `timestamp` as a rounded whole number
    /// @param timestamp Unix timestamp to query
    /// @return Total supply as a whole number
    function totalSupplyAmountRoundedAtTimestamp(uint256 timestamp) public view returns (uint256) {
        return _roundToWholeTokens(totalSupplyAtTimestamp(timestamp));
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
        return _roundTo18dp(claimedTotalSupply());
    }

    /// @notice Get the claimed total supply as a rounded whole number
    /// @dev Returns the value in regular representation (divided by 10^18) rounded to nearest whole token
    /// @dev Uses the actual claimed/minted supply
    /// @return The claimed total supply as a whole number
    function claimedTotalSupplyAmountRounded() public view returns (uint256) {
        return _roundToWholeTokens(claimedTotalSupply());
    }

    /// @notice Round a value to the nearest whole token (18dp representation)
    /// @dev Rounds to nearest 1e18, so when divided by 1e18 it gives a whole number
    /// @param value The value to round
    /// @return The rounded value in 18dp format
    function _roundTo18dp(uint256 value) private pure returns (uint256) {
        uint256 remainder = value % 1e18;
        if (remainder >= 5e17) {
            return value - remainder + 1e18;
        } else {
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
            return (value / 1e18) + 1;
        } else {
            return value / 1e18;
        }
    }

    /// @notice Authorize contract upgrades (UUPS pattern)
    /// @dev Only accounts with ADMIN_ROLE can authorize upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
