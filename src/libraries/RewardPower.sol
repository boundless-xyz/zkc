// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";
import {Constants} from "./Constants.sol";

/**
 * @title RewardPower Library
 * @notice Reward power calculation logic for IRewards interface implementation
 * @dev Reward power = staked_amount / REWARD_POWER_SCALAR (0 if withdrawing)
 */
library RewardPower {

    /**
     * @dev Get current reward power for an account
     * @dev Returns amount / REWARD_POWER_SCALAR if not withdrawing, else 0
     */
    function getRewards(
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
     * @dev Get historical reward power for an account at a specific timestamp
     */
    function getPastRewards(
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
     * @dev Get current total reward power across all users
     */
    function getTotalRewards(
        Checkpoints.GlobalCheckpointStorage storage globalStorage
    ) internal view returns (uint256) {
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        if (globalEpoch == 0) return 0;
        
        Checkpoints.Point memory point = globalStorage.globalPointHistory[globalEpoch];
        return point.amount / Constants.REWARD_POWER_SCALAR;
    }

    /**
     * @dev Get historical total reward power at a specific timestamp
     */
    function getPastTotalRewards(
        Checkpoints.GlobalCheckpointStorage storage globalStorage,
        uint256 timepoint
    ) internal view returns (uint256) {
        uint256 epoch = Checkpoints.findTimestampEpoch(globalStorage, timepoint);
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = globalStorage.globalPointHistory[epoch];
        return point.amount / Constants.REWARD_POWER_SCALAR;
    }
}