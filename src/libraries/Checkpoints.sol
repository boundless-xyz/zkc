// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Constants} from "./Constants.sol";

/// @title Checkpoints Library
/// @notice Shared checkpoint logic for both voting power and reward power tracking
/// @dev This library contains the core Point-based state management used by both
///      voting and reward systems. It follows the standard veToken checkpoint pattern.
library Checkpoints {
    /// @notice Point represents voting/reward power state at a specific moment
    /// @dev TODO: Pack struct for gas savings.
    struct Point {
        /// @notice Amount counting toward voting power (own stake (if not delegated to others) + any votes delegated to user)
        uint256 votingAmount;
        /// @notice Amount counting toward reward power (own stake (if not delegated to others) + any rewards delegated to user)
        uint256 rewardAmount;
        /// @notice Timestamp when recorded
        uint256 updatedAt;
    }

    /// @notice Information about a staked position
    /// @dev TODO: Pack struct for gas savings.
    struct StakeInfo {
        /// @notice Total ZKC amount staked
        uint256 amount;
        /// @notice Withdrawal request timestamp (0 if not withdrawing)
        uint256 withdrawalRequestedAt;
    }

    /// @notice Storage structure for user checkpoint data
    struct UserCheckpointStorage {
        /// @notice Tracks a user's stake evolution + power
        /// @dev Pre-allocated array for gas optimization
        mapping(address account => Point[1000000000]) userPointHistory;
        /// @notice Current index in the user's point history array
        mapping(address account => uint256) userPointEpoch;
    }

    /// @notice Storage structure for global checkpoint data
    struct GlobalCheckpointStorage {
        /// @notice Protocol-wide reward/voting power tracking
        mapping(uint256 => Point) globalPointHistory;
        /// @notice Current index for global point history
        uint256 globalPointEpoch;
    }

    /// @notice Initialize the first global point at index 0
    /// @param self Global checkpoint storage to initialize
    function initializeGlobalPoint(GlobalCheckpointStorage storage self) internal {
        self.globalPointHistory[0] =
            Point({votingAmount: 0, rewardAmount: 0, updatedAt: block.timestamp});
    }

    /// @notice Binary search to find user's point at a specific timestamp
    /// @dev Finds the last voting checkpoint prior to a timepoint
    /// @param self User checkpoint storage to search
    /// @param user Address of the user
    /// @param timestamp Timestamp to search for
    /// @return Epoch index of the checkpoint at or before timestamp
    function findUserTimestampEpoch(UserCheckpointStorage storage self, address user, uint256 timestamp)
        internal
        view
        returns (uint256)
    {
        uint256 min;
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

    /// @notice Binary search to find global point at a specific timestamp
    /// @param self Global checkpoint storage to search
    /// @param timestamp Timestamp to search for
    /// @return Epoch index of the checkpoint at or before timestamp
    function findTimestampEpoch(GlobalCheckpointStorage storage self, uint256 timestamp)
        internal
        view
        returns (uint256)
    {
        uint256 min;
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



    /// @notice Checkpoint function for applying deltas to both voting and reward power
    /// @dev Updates user and global checkpoints with the specified deltas
    /// @param userStorage User checkpoint storage to update
    /// @param globalStorage Global checkpoint storage to update
    /// @param account Address whose power is changing
    /// @param votingDelta Amount to add/remove from voting power
    /// @param rewardDelta Amount to add/remove from reward power
    function checkpointDelta(
        UserCheckpointStorage storage userStorage,
        GlobalCheckpointStorage storage globalStorage,
        address account,
        int256 votingDelta,
        int256 rewardDelta
    ) internal {
        // Get current user point
        (Point memory lastUserPoint,) = _getUserLastPoint(userStorage, account);

        // Create new user point with deltas applied
        int256 newVotingAmount = int256(lastUserPoint.votingAmount) + votingDelta;
        int256 newRewardAmount = int256(lastUserPoint.rewardAmount) + rewardDelta;
        
        // Sanity check for underflow, which would inflate power on cast to uint256
        require(newVotingAmount >= 0, "Checkpoints: voting amount underflow");
        require(newRewardAmount >= 0, "Checkpoints: reward amount underflow");
        
        Point memory newUserPoint = Point({
            votingAmount: uint256(newVotingAmount),
            rewardAmount: uint256(newRewardAmount),
            updatedAt: block.timestamp
        });

        // Update user checkpoint
        _updateUserCheckpoint(userStorage, account, newUserPoint);

        // Update global checkpoint with the same deltas
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        Point memory lastGlobalPoint = globalEpoch > 0
            ? globalStorage.globalPointHistory[globalEpoch]
            : Point({votingAmount: 0, rewardAmount: 0, updatedAt: block.timestamp});

        int256 newGlobalVotingAmount = int256(lastGlobalPoint.votingAmount) + votingDelta;
        int256 newGlobalRewardAmount = int256(lastGlobalPoint.rewardAmount) + rewardDelta;
        
        // Sanity check for underflow, which would inflate power on cast to uint256
        require(newGlobalVotingAmount >= 0, "Checkpoints: global voting amount underflow");
        require(newGlobalRewardAmount >= 0, "Checkpoints: global reward amount underflow");
        
        Point memory newGlobalPoint = Point({
            votingAmount: uint256(newGlobalVotingAmount),
            rewardAmount: uint256(newGlobalRewardAmount),
            updatedAt: block.timestamp
        });

        // Update global point history
        _updateGlobalCheckpointHistory(globalStorage, newGlobalPoint);
    }

    /// @notice Checkpoint function for vote delegation
    /// @dev Updates only the votingAmount field of Points for the user
    /// @param userStorage User checkpoint storage to update
    /// @param account Address whose voting power is changing
    /// @param votingDelta Amount to add (positive) or remove (negative) from voting power
    function checkpointVoteDelegation(UserCheckpointStorage storage userStorage, address account, int256 votingDelta)
        internal
    {
        // Get current user point
        (Point memory lastPoint,) = _getUserLastPoint(userStorage, account);

        // Create new point with updated voting amount
        int256 newVotingAmount = int256(lastPoint.votingAmount) + votingDelta;
        
        // Sanity check for underflow, which would inflate power on cast to uint256
        require(newVotingAmount >= 0, "Checkpoints: voting amount underflow");
        
        Point memory newPoint = Point({
            votingAmount: uint256(newVotingAmount),
            rewardAmount: lastPoint.rewardAmount, // Keep reward amount unchanged
            updatedAt: block.timestamp
        });

        // Update user checkpoint only (no global update needed for delegation)
        _updateUserCheckpoint(userStorage, account, newPoint);
    }

    /// @notice Checkpoint function for reward delegation
    /// @dev Updates only the rewardAmount field of Points for the user
    /// @param userStorage User checkpoint storage to update
    /// @param account Address whose reward power is changing
    /// @param rewardDelta Amount to add (positive) or remove (negative) from reward power
    function checkpointRewardDelegation(UserCheckpointStorage storage userStorage, address account, int256 rewardDelta)
        internal
    {
        // Get current user point
        (Point memory lastPoint,) = _getUserLastPoint(userStorage, account);

        // Create new point with updated reward amount
        int256 newRewardAmount = int256(lastPoint.rewardAmount) + rewardDelta;
        
        // Sanity check for underflow, which would inflate power on cast to uint256
        require(newRewardAmount >= 0, "Checkpoints: reward amount underflow");
        
        Point memory newPoint = Point({
            votingAmount: lastPoint.votingAmount, // Keep voting amount unchanged
            rewardAmount: uint256(newRewardAmount),
            updatedAt: block.timestamp
        });

        // Update user checkpoint only (no global update needed for delegation)
        _updateUserCheckpoint(userStorage, account, newPoint);
    }

    /// @notice Checkpoint function that handles delegation-aware stake updates
    /// @dev Updates user checkpoints based on delegation status and global checkpoints
    /// @param userStorage User checkpoint storage to update
    /// @param globalStorage Global checkpoint storage to update
    /// @param account Address of the account being checkpointed
    /// @param oldStake Previous stake state
    /// @param newStake New stake state
    /// @param isVoteDelegated Whether votes are delegated (to someone other than self)
    /// @param isRewardDelegated Whether rewards are delegated (to someone other than self)
    /// @return userVotingDelta The voting power delta for the user (for delegation updates)
    /// @return userRewardDelta The reward power delta for the user (for delegation updates)
    function checkpointWithDelegation(
        UserCheckpointStorage storage userStorage,
        GlobalCheckpointStorage storage globalStorage,
        address account,
        StakeInfo memory oldStake,
        StakeInfo memory newStake,
        bool isVoteDelegated,
        bool isRewardDelegated
    ) internal returns (int256 userVotingDelta, int256 userRewardDelta) {
        // Calculate the change in stake amount
        int256 stakeDelta = int256(newStake.amount) - int256(oldStake.amount);

        // Calculate deltas for user's own checkpoint
        userVotingDelta = isVoteDelegated ? int256(0) : stakeDelta;
        userRewardDelta = isRewardDelegated ? int256(0) : stakeDelta;

        // If either votes or rewards are not delegated, update user's checkpoint with deltas
        if (userVotingDelta != 0 || userRewardDelta != 0) {
            // Get current user point
            (Point memory lastUserPoint,) = _getUserLastPoint(userStorage, account);

            // Create new user point with deltas applied
            int256 newVotingAmount = int256(lastUserPoint.votingAmount) + userVotingDelta;
            int256 newRewardAmount = int256(lastUserPoint.rewardAmount) + userRewardDelta;
            
            // Sanity check for underflow, which would inflate power on cast to uint256
            require(newVotingAmount >= 0, "Checkpoints: voting amount underflow");
            require(newRewardAmount >= 0, "Checkpoints: reward amount underflow");
            
            Point memory newUserPoint = Point({
                votingAmount: uint256(newVotingAmount),
                rewardAmount: uint256(newRewardAmount),
                updatedAt: block.timestamp
            });

            // Update user checkpoint
            _updateUserCheckpoint(userStorage, account, newUserPoint);
        }

        // Update global checkpoint for stake changes
        updateGlobalCheckpoint(globalStorage, oldStake, newStake);

        // Return deltas for the caller to handle delegation updates if needed
        return (isVoteDelegated ? stakeDelta : int256(0), isRewardDelegated ? stakeDelta : int256(0));
    }

    /// @notice Update global checkpoint for stake changes
    /// @dev Updates global totals based on effective stake amounts
    /// @param globalStorage Global checkpoint storage to update
    /// @param oldStake Previous stake state
    /// @param newStake New stake state
    function updateGlobalCheckpoint(
        GlobalCheckpointStorage storage globalStorage,
        StakeInfo memory oldStake,
        StakeInfo memory newStake
    ) internal {
        // Calculate effective amounts (0 if withdrawing)
        uint256 oldEffectiveAmount = oldStake.withdrawalRequestedAt > 0 ? 0 : oldStake.amount;
        uint256 newEffectiveAmount = newStake.withdrawalRequestedAt > 0 ? 0 : newStake.amount;

        // Load current global point
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        Point memory lastGlobalPoint;
        if (globalEpoch > 0) {
            lastGlobalPoint = globalStorage.globalPointHistory[globalEpoch];
        }

        // Calculate new global point
        Point memory newGlobalPoint = Point({
            votingAmount: lastGlobalPoint.votingAmount + newEffectiveAmount - oldEffectiveAmount,
            rewardAmount: lastGlobalPoint.rewardAmount + newEffectiveAmount - oldEffectiveAmount,
            updatedAt: block.timestamp
        });

        // Update global checkpoint
        _updateGlobalCheckpointHistory(globalStorage, newGlobalPoint);
    }

    /// @notice Helper function to get user's last checkpoint or create a default one
    /// @param userStorage User checkpoint storage
    /// @param account Address of the user
    /// @return lastPoint The user's last checkpoint point or a default zero point
    /// @return userEpoch The current user epoch
    function _getUserLastPoint(
        UserCheckpointStorage storage userStorage,
        address account
    ) internal view returns (Point memory lastPoint, uint256 userEpoch) {
        userEpoch = userStorage.userPointEpoch[account];
        lastPoint = userEpoch > 0
            ? userStorage.userPointHistory[account][userEpoch]
            : Point({votingAmount: 0, rewardAmount: 0, updatedAt: block.timestamp});
    }

    /// @notice Helper function to update user checkpoint with a new point
    /// @param userStorage User checkpoint storage to update
    /// @param account Address of the user
    /// @param newPoint New point to store
    function _updateUserCheckpoint(
        UserCheckpointStorage storage userStorage,
        address account,
        Point memory newPoint
    ) internal {
        uint256 userEpoch = userStorage.userPointEpoch[account] + 1;
        userStorage.userPointEpoch[account] = userEpoch;
        userStorage.userPointHistory[account][userEpoch] = newPoint;
    }

    /// @notice Helper function to update global checkpoint history with proper timestamp handling
    /// @param globalStorage Global checkpoint storage to update
    /// @param newGlobalPoint New global point to store
    function _updateGlobalCheckpointHistory(
        GlobalCheckpointStorage storage globalStorage,
        Point memory newGlobalPoint
    ) internal {
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        Point memory lastGlobalPoint = globalEpoch > 0 
            ? globalStorage.globalPointHistory[globalEpoch]
            : Point({votingAmount: 0, rewardAmount: 0, updatedAt: 0});
        
        if (globalEpoch > 0 && lastGlobalPoint.updatedAt == block.timestamp) {
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
