// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Constants} from "./Constants.sol";

/**
 * @title Checkpoints Library
 * @notice Shared checkpoint logic for both voting power and reward power tracking
 * @dev This library contains the core Point-based state management used by both 
 *      voting and reward systems. It follows the standard veToken checkpoint pattern.
 *      
 *      This is a pure extraction of existing logic from veZKC.sol without modification.
 */
library Checkpoints {
    
    /**
     * @dev Point represents staking state at a specific moment
     * @dev No decay - powers are simply amount / scalar
     * @dev Withdrawing flag indicates if user is in withdrawal period (powers = 0)
     */
    struct Point {
        /// @dev Staked ZKC amount
        uint256 amount;
        /// @dev Timestamp when recorded
        uint256 updatedAt;
        /// @dev Whether user is in withdrawal period (powers drop to 0)
        bool withdrawing;
    }

    struct StakeInfo {
        /// @dev Total ZKC amount staked
        uint256 amount;
        /// @dev Withdrawal request timestamp (0 if not withdrawing)
        uint256 withdrawalRequestedAt;
    }

    /**
     * @dev Storage structure for user checkpoint data
     */
    struct UserCheckpointStorage {
        /// @dev Pre-allocated array tracking power evolution per account (gas optimization)
        mapping(address account => Point[1000000000]) userPointHistory;
        /// @dev Current index in the user's point history array
        mapping(address account => uint256) userPointEpoch;
    }

    /**
     * @dev Storage structure for global checkpoint data
     */
    struct GlobalCheckpointStorage {
        /// @dev Protocol-wide voting power tracking
        mapping(uint256 => Point) globalPointHistory;
        /// @dev Current index for global point history
        uint256 globalPointEpoch;
        // Removed slopeChanges - no longer needed without decay
    }

    /**
     * @dev Initialize the first global point at index 0
     */
    function initializeGlobalPoint(GlobalCheckpointStorage storage self) internal {
        self.globalPointHistory[0] = Point({
            amount: 0,
            updatedAt: block.timestamp,
            withdrawing: false
        });
    }

    // Removed timestampFloorToWeek - no longer needed without week-based locks

    /**
     * @dev Binary search to find user's point at a specific timestamp
     * @dev Finds the last voting checkpoint prior to a timepoint
     */
    function findUserTimestampEpoch(
        UserCheckpointStorage storage self,
        address user, 
        uint256 timestamp
    ) internal view returns (uint256) {
        uint256 min = 0;
        uint256 max = self.userPointEpoch[user];

        // Shortcut to find the most recent checkpoint, which if claims
        // are frequent, should save gas.
        if (self.userPointHistory[user][max].updatedAt <= timestamp) {
            return max;
        }
        
        while (min < max) {
            uint256 mid = (min + max + 1) / 2;
            if (self.userPointHistory[user][mid].updatedAt <= timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        
        return min;
    }
    
    /**
     * @dev Binary search to find global point at a specific timestamp
     */
    function findTimestampEpoch(
        GlobalCheckpointStorage storage self,
        uint256 timestamp
    ) internal view returns (uint256) {
        uint256 min = 0;
        uint256 max = self.globalPointEpoch;

        // Shortcut to find the most recent checkpoint, which if claims
        // are frequent, should save gas.
        if (self.globalPointHistory[max].updatedAt <= timestamp) {
            return max;
        }
        
        while (min < max) {
            uint256 mid = (min + max + 1) / 2;
            if (self.globalPointHistory[mid].updatedAt <= timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        
        return min;
    }

    /**
     * @dev Get user point at specific epoch
     */
    function getUserPoint(
        UserCheckpointStorage storage self,
        address user,
        uint256 epoch
    ) internal view returns (Point memory) {
        return self.userPointHistory[user][epoch];
    }

    /**
     * @dev Get global point at specific epoch
     */
    function getGlobalPoint(
        GlobalCheckpointStorage storage self,
        uint256 epoch
    ) internal view returns (Point memory) {
        return self.globalPointHistory[epoch];
    }

    /**
     * @dev Get current user epoch
     */
    function getUserEpoch(
        UserCheckpointStorage storage self,
        address user
    ) internal view returns (uint256) {
        return self.userPointEpoch[user];
    }

    /**
     * @dev Get current global epoch
     */
    function getGlobalEpoch(
        GlobalCheckpointStorage storage self
    ) internal view returns (uint256) {
        return self.globalPointEpoch;
    }

    /**
     * @dev Main checkpoint function that updates user and global points
     * @dev Tracks stake amount changes and withdrawal status
     */
    function checkpoint(
        UserCheckpointStorage storage userStorage,
        GlobalCheckpointStorage storage globalStorage,
        address account, 
        StakeInfo memory oldStake, 
        StakeInfo memory newStake
    ) internal {
        // Create old point from previous stake state
        Point memory userOldPoint;
        if (oldStake.amount > 0) {
            userOldPoint = Point({
                amount: oldStake.amount,
                updatedAt: block.timestamp,
                withdrawing: oldStake.withdrawalRequestedAt > 0
            });
        }
        
        // Create new point from new stake state  
        Point memory userNewPoint;
        if (newStake.amount > 0) {
            userNewPoint = Point({
                amount: newStake.amount,
                updatedAt: block.timestamp,
                withdrawing: newStake.withdrawalRequestedAt > 0
            });
        }
        
        // Update user point history
        uint256 userEpoch = userStorage.userPointEpoch[account] + 1;
        userStorage.userPointEpoch[account] = userEpoch;
        userStorage.userPointHistory[account][userEpoch] = userNewPoint;
        
        // Load the most recent global point
        Point memory lastGlobalPoint = Point({amount: 0, updatedAt: block.timestamp, withdrawing: false});
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        if (globalEpoch > 0) {
            lastGlobalPoint = globalStorage.globalPointHistory[globalEpoch];
        }

        // Calculate new global point by applying user's changes
        // When withdrawing, effective amount is 0 (powers are 0)
        uint256 oldEffectiveAmount = userOldPoint.withdrawing ? 0 : userOldPoint.amount;
        uint256 newEffectiveAmount = userNewPoint.withdrawing ? 0 : userNewPoint.amount;
        
        Point memory newGlobalPoint = Point({
            amount: lastGlobalPoint.amount + newEffectiveAmount - oldEffectiveAmount,
            updatedAt: block.timestamp,
            withdrawing: false // Global never withdraws
        });

        // Update global point history
        // Check if we already have a global point at this timestamp (multiple txs in same block)
        if (globalEpoch > 0 && globalStorage.globalPointHistory[globalEpoch].updatedAt == block.timestamp) {
            // Update existing point at this timestamp
            globalStorage.globalPointHistory[globalEpoch] = newGlobalPoint;
        } else {
            // Create new global point
            globalEpoch += 1;
            globalStorage.globalPointHistory[globalEpoch] = newGlobalPoint;
            globalStorage.globalPointEpoch = globalEpoch;
        }
    }
}