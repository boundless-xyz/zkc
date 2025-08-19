// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";
import {Constants} from "./Constants.sol";

/**
 * @title RewardPower Library
 * @notice Reward power calculation logic for IRewards interface implementation
 * @dev Provides both staking rewards (REWARD_POWER_SCALAR) and PoVW reward cap (POVW_REWARD_CAP_SCALAR) calculations
 */
library RewardPower {

    /**
     * @dev Get current staking rewards for an account
     * @dev Returns amount / REWARD_POWER_SCALAR if not withdrawing, else 0
     */
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

    /**
     * @dev Get historical staking rewards for an account at a specific timestamp
     */
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

    /**
     * @dev Get current total staking rewards across all users
     */
    function getTotalStakingRewards(
        Checkpoints.GlobalCheckpointStorage storage globalStorage
    ) internal view returns (uint256) {
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        if (globalEpoch == 0) return 0;
        
        Checkpoints.Point memory point = globalStorage.globalPointHistory[globalEpoch];
        return point.amount / Constants.REWARD_POWER_SCALAR;
    }

    /**
     * @dev Get historical total staking rewards at a specific timestamp
     */
    function getPastTotalStakingRewards(
        Checkpoints.GlobalCheckpointStorage storage globalStorage,
        uint256 timepoint
    ) internal view returns (uint256) {
        uint256 epoch = Checkpoints.findTimestampEpoch(globalStorage, timepoint);
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = globalStorage.globalPointHistory[epoch];
        return point.amount / Constants.REWARD_POWER_SCALAR;
    }

    /**
     * @dev Get current PoVW reward cap for an account
     * @dev Returns amount / POVW_REWARD_CAP_SCALAR if not withdrawing, else 0
     */
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

    /**
     * @dev Get historical PoVW reward cap for an account at a specific timestamp
     */
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