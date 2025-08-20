// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";
import {Constants} from "./Constants.sol";

/// @title RewardPower Library
/// @notice Reward power calculation logic for IRewards interface implementation
/// @dev Provides both staking rewards (REWARD_POWER_SCALAR) and PoVW reward cap (POVW_REWARD_CAP_SCALAR) calculations
library RewardPower {

    /// @notice Get current staking rewards for an account
    /// @dev Returns amount / REWARD_POWER_SCALAR if not withdrawing, else 0
    /// @param userStorage User checkpoint storage
    /// @param account Address to query
    /// @return Current reward power
    function getStakingRewards(
        Checkpoints.UserCheckpointStorage storage userStorage,
        address account
    ) internal view returns (uint256) {
        uint256 epoch = userStorage.userPointEpoch[account];
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        if (point.withdrawing) return 0;
        return point.amount / Constants.REWARD_POWER_SCALAR;
    }

    /// @notice Get historical staking rewards for an account at a specific timestamp
    /// @param userStorage User checkpoint storage
    /// @param account Address to query
    /// @param timepoint Historical timestamp
    /// @return Reward power at the specified timestamp
    function getPastStakingRewards(
        Checkpoints.UserCheckpointStorage storage userStorage,
        address account,
        uint256 timepoint
    ) internal view returns (uint256) {
        uint256 epoch = Checkpoints.findUserTimestampEpoch(userStorage, account, timepoint);
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        if (point.withdrawing) return 0;
        return point.amount / Constants.REWARD_POWER_SCALAR;
    }

    /// @notice Get current total staking rewards across all users
    /// @param globalStorage Global checkpoint storage
    /// @return Current total reward power
    function getTotalStakingRewards(
        Checkpoints.GlobalCheckpointStorage storage globalStorage
    ) internal view returns (uint256) {
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        if (globalEpoch == 0) return 0;
        
        Checkpoints.Point memory point = globalStorage.globalPointHistory[globalEpoch];
        return point.amount / Constants.REWARD_POWER_SCALAR;
    }

    /// @notice Get historical total staking rewards at a specific timestamp
    /// @param globalStorage Global checkpoint storage
    /// @param timepoint Historical timestamp
    /// @return Total reward power at the specified timestamp
    function getPastTotalStakingRewards(
        Checkpoints.GlobalCheckpointStorage storage globalStorage,
        uint256 timepoint
    ) internal view returns (uint256) {
        uint256 epoch = Checkpoints.findTimestampEpoch(globalStorage, timepoint);
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = globalStorage.globalPointHistory[epoch];
        return point.amount / Constants.REWARD_POWER_SCALAR;
    }

    /// @notice Get current PoVW reward cap for an account
    /// @dev Returns amount / POVW_REWARD_CAP_SCALAR if not withdrawing, else 0
    /// @param userStorage User checkpoint storage
    /// @param account Address to query
    /// @return Current PoVW reward cap
    function getPoVWRewardCap(
        Checkpoints.UserCheckpointStorage storage userStorage,
        address account
    ) internal view returns (uint256) {
        uint256 epoch = userStorage.userPointEpoch[account];
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        if (point.withdrawing) return 0;
        return point.amount / Constants.POVW_REWARD_CAP_SCALAR;
    }

    /// @notice Get historical PoVW reward cap for an account at a specific timestamp
    /// @param userStorage User checkpoint storage
    /// @param account Address to query
    /// @param timepoint Historical timestamp
    /// @return PoVW reward cap at the specified timestamp
    function getPastPoVWRewardCap(
        Checkpoints.UserCheckpointStorage storage userStorage,
        address account,
        uint256 timepoint
    ) internal view returns (uint256) {
        uint256 epoch = Checkpoints.findUserTimestampEpoch(userStorage, account, timepoint);
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        if (point.withdrawing) return 0;
        return point.amount / Constants.POVW_REWARD_CAP_SCALAR;
    }
}