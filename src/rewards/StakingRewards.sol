// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ZKC} from "../ZKC.sol";
import {IRewards} from "../interfaces/IRewards.sol";

/// @notice Error thrown when a user tries to claim rewards for an epoch they have already claimed
error AlreadyClaimed(uint256 epoch);

/**
 * @title StakingRewards
 * @notice Contract for distributing staking rewards based on veZKC staking positions
 * @dev Users can claim rewards for specific epochs based on their staking value
 */
contract StakingRewards is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// @notice ZKC token contract
    ZKC public zkc;

    /// @notice veZKC rewards interface for getting staking positions
    IRewards public veZKC;

    /// @dev Mapping to track if a user has claimed rewards for an epoch
    mapping(uint256 => mapping(address => bool)) private _userClaimed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _zkc, address _veZKC, address _admin) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        zkc = ZKC(_zkc);
        veZKC = IRewards(_veZKC);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Claim rewards for the given epochs
     * @param epochs The epochs to claim rewards for
     * @return amount The amount of rewards claimed
     */
    function claimRewards(uint256[] calldata epochs) external nonReentrant returns (uint256 amount) {
        return _claim(msg.sender, epochs);
    }

    /**
     * @notice Calculate the rewards a user is owed for the given epochs
     * @param user The user address
     * @param epochs The epochs to calculate rewards for
     * @return rewards The rewards owed
     */
    function calculateRewards(address user, uint256[] calldata epochs) external returns (uint256[] memory) {
        return _calculate(user, epochs);
    }

    /**
     * @notice Check if a user has claimed rewards for a specific epoch
     * @param user The user address
     * @param epoch The epoch to check
     * @return claimed Whether rewards have been claimed
     */
    function hasUserClaimedRewards(address user, uint256 epoch) external view returns (bool claimed) {
        return _userClaimed[epoch][user];
    }

    /**
     * @notice Get the current epoch from the ZKC contract
     * @return currentEpoch The current epoch number
     */
    function getCurrentEpoch() external view returns (uint256 currentEpoch) {
        return zkc.getCurrentEpoch();
    }

    /**
     * @notice Get the end timestamp for a specific epoch
     * @param epoch The epoch number
     * @return endTimestamp The end timestamp of the epoch
     */
    function _epochEndTimestamp(uint256 epoch) internal view returns (uint256) {
        return zkc.getEpochEndTime(epoch);
    }

    /**
     * @notice Internal function to calculate the rewards a user is owed for the given epochs
     * @param user The user address
     * @param epochs The epochs to calculate rewards for
     * @return rewards The list of rewards owed
     */
    function _calculate(address user, uint256[] calldata epochs) internal returns (uint256[] memory) {
        uint256 currentEpoch = zkc.getCurrentEpoch();
        uint256[] memory rewards = new uint256[](epochs.length);
        for (uint256 i = 0; i < epochs.length; i++) {
            uint256 epoch = epochs[i];
            if (epoch >= currentEpoch) continue; // cannot claim ongoing/future epoch
            uint256 snapshotTime = _epochEndTimestamp(epoch);
            uint256 userPower = veZKC.getPastStakingRewards(user, snapshotTime);
            if (userPower == 0) continue;
            uint256 totalPower = veZKC.getPastTotalStakingRewards(snapshotTime);
            if (totalPower == 0) continue;
            uint256 emission = zkc.getStakingEmissionsForEpoch(epoch);
            rewards[i] = (emission * userPower) / totalPower;
        }
        return rewards;
    }

    /**
     * @notice Internal function to claim rewards for a user in the given epochs
     * @param user The user address
     * @param epochs The epochs to claim rewards for
     * @return amount The amount of rewards claimed
     */
    function _claim(address user, uint256[] calldata epochs) internal returns (uint256 amount) {
        uint256[] memory amounts = _calculate(user, epochs);
        uint256 currentEpoch = zkc.getCurrentEpoch();
        for (uint256 i = 0; i < epochs.length; i++) {
            uint256 epoch = epochs[i];
            if (_userClaimed[epoch][user]) revert AlreadyClaimed(epoch);
            // Epoch must have ended
            if (epoch >= currentEpoch) revert ZKC.EpochNotEnded(epoch);
            _userClaimed[epoch][user] = true;
            amount += amounts[i];
        }
        if (amount == 0) return 0;
        zkc.mintStakingRewardsForRecipient(user, amount);
        return amount;
    }

    /**
     * @notice Authorize upgrades to this contract
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
