// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";

/**
 * @title RewardPower Library
 * @notice Reward power calculation logic for IRewards interface implementation
 * @dev This library handles all reward-specific calculations while using shared checkpoint state
 *      Reward power equals staked amount and does not decay over time
 */
library RewardPower {

    /**
     * @dev Get current reward power for an account
     * @dev Reward power equals the staked amount and doesn't decay
     */
    function getRewards(
        Checkpoints.UserCheckpointStorage storage userStorage,
        address account
    ) internal view returns (uint256) {
        uint256 epoch = userStorage.userPointEpoch[account];
        if (epoch == 0) return 0;
        
        return userStorage.userPointHistory[account][epoch].amount;
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
        
        return userStorage.userPointHistory[account][epoch].amount;
    }

    /**
     * @dev Get current total reward power across all users
     */
    function getTotalRewards(
        Checkpoints.GlobalCheckpointStorage storage globalStorage
    ) internal view returns (uint256) {
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        if (globalEpoch == 0) return 0;
        
        return globalStorage.globalPointHistory[globalEpoch].amount;
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
        
        return globalStorage.globalPointHistory[epoch].amount;
    }
}