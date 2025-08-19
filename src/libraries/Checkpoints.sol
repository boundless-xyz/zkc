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
     * @dev Point represents voting power at a specific moment that decays linearly over time
     * @dev Formula: voting_power(t) = bias - slope * (t - ts)
     * @dev This follows the standard veToken model where voting_power = amount * time_remaining / max_time
     * @dev Also tracks reward power which equals staked amount and doesn't decay
     */
    struct Point {
        /// @dev Voting power at timestamp ts (y-intercept)
        int128 bias;
        /// @dev Rate of decay per second
        int128 slope;
        /// @dev Timestamp when recorded
        uint256 updatedAt;
        /// @dev Staked amount for reward power (user) or total staked (global)
        uint256 amount;
    }

    struct LockInfo {
        /// @dev Total ZKC amount locked
        uint256 amount;
        /// @dev When the lock expires
        uint256 lockEnd;
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
        /// @dev Scheduled global slope adjustments when locks expire (timestamp => slope delta)
        mapping(uint256 timestamp => int128) slopeChanges;
    }

    /**
     * @dev Initialize the first global point at index 0
     */
    function initializeGlobalPoint(GlobalCheckpointStorage storage self) internal {
        self.globalPointHistory[0] = Point({
            bias: 0,
            slope: 0,
            updatedAt: block.timestamp,
            amount: 0
        });
    }

    /**
     * @dev Round timestamp down to nearest week boundary
     */
    function timestampFloorToWeek(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / Constants.WEEK) * Constants.WEEK;
    }

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
     * @dev Direct extraction of existing _checkpoint logic without modification
     * @dev Following standard veToken pattern with explicit old/new lock states
     */
    function checkpoint(
        UserCheckpointStorage storage userStorage,
        GlobalCheckpointStorage storage globalStorage,
        address account, 
        LockInfo memory oldLock, 
        LockInfo memory newLock
    ) internal {
        // Track the users old point (if one exists, i.e. we are topping up or extending a lock)
        Point memory userOldPoint;
        // Track the users new point (either updated from old point, or newly created)
        Point memory userNewPoint;
        
        // Track the impact on the global point's slope value as a result of the user's lock changes.
        int128 globalOldSlopeDelta = 0;
        int128 globalNewSlopeDelta = 0;
        
        // If an old lock was provided, calculate the point that we will remove from the oldLock state.
        // For expired locks, we calculate a point, with the amount, but leave bias/slope empty. Since the lock has
        // already expired, voting power is already 0 as it must have decayed to 0, so no need to apply any
        // bias/slope changes, but we must remove the amount value from user + global tracking.
        if (oldLock.amount > 0) {
            if (oldLock.lockEnd > block.timestamp) {
                // Active lock: calculate voting power and slope
                int128 oldSlope = int128(int256(oldLock.amount)) / Constants.iMAX_STAKE_TIME_S;
                int128 oldRemainingTime = int128(int256(oldLock.lockEnd - block.timestamp));
                int128 oldBias = oldSlope * oldRemainingTime;
                
                userOldPoint = Point({
                    bias: int128(int256(oldBias)),
                    slope: oldSlope,
                    updatedAt: block.timestamp,
                    amount: oldLock.amount
                });
            } else {
                // Expired lock: we don't need to do anything w.r.t bias/slope, as its already
                // expired so already decayed to 0, so leave as 0. Amount we do need to adjust,
                // as it doesn't decay, so we set it here.
                userOldPoint = Point({
                    bias: 0,
                    slope: 0,
                    updatedAt: block.timestamp,
                    amount: oldLock.amount
                });
            }
        }
        
        // Calculate new point from explicit newLock state.
        // For reward power tracking, we need to track amount even for expired locks
        if (newLock.amount > 0) {
            if (newLock.lockEnd > block.timestamp) {
                // Active lock: calculate voting power and slope
                int128 newSlope = int128(int256(newLock.amount)) / Constants.iMAX_STAKE_TIME_S;
                int128 newRemainingTime = int128(int256(newLock.lockEnd - block.timestamp));
                int128 newBias = newSlope * newRemainingTime;
                
                userNewPoint = Point({
                    bias: int128(int256(newBias)),
                    slope: newSlope,
                    updatedAt: block.timestamp,
                    amount: newLock.amount
                });
            } else {
                // Expired lock: voting power is 0 already, but amount persists for reward tracking
                userNewPoint = Point({
                    bias: 0,
                    slope: 0,
                    updatedAt: block.timestamp,
                    amount: newLock.amount
                });
            }
        }

        // Read slope changes that are already scheduled at these timestamps.
        // oldLock.lockEnd can be in the past or in the future
        // newLock.lockEnd can either be in the future, or 0 (used for unstaking after expiry)
        globalOldSlopeDelta = globalStorage.slopeChanges[oldLock.lockEnd];
        if (newLock.lockEnd != 0) {
            if (newLock.lockEnd == oldLock.lockEnd) {
                globalNewSlopeDelta = globalOldSlopeDelta;
            } else {
                globalNewSlopeDelta = globalStorage.slopeChanges[newLock.lockEnd];
            }
        }
        
        // Update user point history
        uint256 userEpoch = userStorage.userPointEpoch[account] + 1;
        userStorage.userPointEpoch[account] = userEpoch;
        userStorage.userPointHistory[account][userEpoch] = userNewPoint;
        
        // Load the most recent global point. Globals point can be created as part of 
        // backfills (in which case they fall on week boundaries), or as part of user actions such as stake/unstake/extend.
        // If the global point is created as part of a backfill, it will have a timestamp that is a multiple of the week.
        // If the global point is created as part of a user action, it will have a timestamp that is not a multiple of the week.
        // We need to backfill the global point history for all weeks before the current block timestamp.
        // We do this by iterating over the weeks before the current block timestamp, and applying the slope changes for each week.
        // We then apply the user's changes to the global point, and store the new latest global point.
        // We then schedule the slope changes for the next week.
        Point memory lastGlobalPoint = Point({bias: 0, slope: 0, updatedAt: block.timestamp, amount: 0});
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        if (globalEpoch > 0) {
            lastGlobalPoint = globalStorage.globalPointHistory[globalEpoch];
        }

        uint256 lastCheckpoint = lastGlobalPoint.updatedAt;
        
        // Backfill weekly global points.
        // This ensures getPastTotalSupply works correctly for any timestamp 
        // (since timestamps are always rounded down to the week on lock creation/extension)
        {
            uint256 curWeek = timestampFloorToWeek(lastCheckpoint); // Round down to week
            
            for (uint256 i = 0; i < 255; i++) {
                curWeek += Constants.WEEK;
                int128 currentScheduledSlopeChange = 0;
                
                if (curWeek > block.timestamp) {
                    curWeek = block.timestamp; // Don't go beyond current time
                } else {
                    currentScheduledSlopeChange = globalStorage.slopeChanges[curWeek]; // Get slope change for this week
                }
                
                // Compute the delta in bias between the last checkpoint and the current week we are backfilling to.
                // Apply it to the last global point's bias.
                int128 biasDelta = lastGlobalPoint.slope * int128(int256(curWeek - lastCheckpoint));
                lastGlobalPoint.bias -= biasDelta;

                // If decayed to zero mid week, bias could be negative in following week.
                // Ensure bias never goes negative.
                if (lastGlobalPoint.bias < 0) {
                    lastGlobalPoint.bias = 0;
                }

                // Apply the slope change for this week to the last global point's slope.
                lastGlobalPoint.slope += currentScheduledSlopeChange;
                
                // Slope can never go negative. Added as a sanity check.
                if (lastGlobalPoint.slope < 0) {
                    lastGlobalPoint.slope = 0;
                }

                lastCheckpoint = curWeek;
                lastGlobalPoint.updatedAt = curWeek;
                globalEpoch += 1;
                
                // If the last global point timestamp is the same as the block timestamp, then
                // we don't store it yet. We only store backfills in this loop. 
                // The point for the current block timestamp will be our new latest point and we still need to 
                // apply the new user request's changes to it.
                if (lastGlobalPoint.updatedAt == block.timestamp) {
                    break;
                } else { 
                    globalStorage.globalPointHistory[globalEpoch] = lastGlobalPoint;
                }                
            }
        }

        // At this point we have backfilled the global point history for all weeks before the current block timestamp.
        // Now apply the user's changes, and store the new latest global point.
        Point memory newGlobalPoint = Point({
            bias: lastGlobalPoint.bias + userNewPoint.bias - userOldPoint.bias,
            slope: lastGlobalPoint.slope + userNewPoint.slope - userOldPoint.slope,
            updatedAt: block.timestamp,
            amount: lastGlobalPoint.amount + userNewPoint.amount - userOldPoint.amount
        });
        
        // Ensure non-negative bias and slope
        if (newGlobalPoint.bias < 0) {
            newGlobalPoint.bias = 0;
        }

        if (newGlobalPoint.slope < 0) {
            newGlobalPoint.slope = 0;
        }

        // If we haven't already created a global point at the current block timestamp,
        // we increment the global point epoch so we can store it new.
        // 
        // If we already created a global point at this block timestamp due to a previous
        // transaction within the same block, we don't need to increment the global point epoch. 
        // We instead just update the existing global point.

        if (globalEpoch != 1 && globalStorage.globalPointHistory[globalEpoch - 1].updatedAt == block.timestamp) {
            // We already incremented globalEpoch in loop above, subtract so that we overwrite the existing point.
            globalStorage.globalPointHistory[globalEpoch - 1] = newGlobalPoint;
        } else {
            // more than one global point may have been written, so we update epoch
            globalStorage.globalPointHistory[globalEpoch] = newGlobalPoint;
            globalStorage.globalPointEpoch = globalEpoch;
        }
        
        // Schedule slope changes.
        if (oldLock.lockEnd > block.timestamp) {
            // Cancel out the slope change that was previously scheduled by the old point.
            // When a lock is removed or expires, slope becomes less negative (decay slows), 
            // so we add to cancel out the decay.
            globalOldSlopeDelta += userOldPoint.slope;
            // If it is a new deposit, not extension, we apply the new slope to the same point.
            if (newLock.lockEnd == oldLock.lockEnd) {
                globalOldSlopeDelta -= userNewPoint.slope;
            }
            globalStorage.slopeChanges[oldLock.lockEnd] = globalOldSlopeDelta;
        }

        if (newLock.lockEnd > block.timestamp) {
            // If its an extension, we schedule the slope to disappear at the new point.
            if (newLock.lockEnd > oldLock.lockEnd) {
                globalNewSlopeDelta -= userNewPoint.slope;
                globalStorage.slopeChanges[newLock.lockEnd] = globalNewSlopeDelta;
            }
        }
    }
}