// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";
import {Constants} from "./Constants.sol";

/**
 * @title VotingPower Library
 * @notice Voting power calculation logic for IVotes interface implementation
 * @dev This library handles all voting-specific calculations while using shared checkpoint state
 */
library VotingPower {

    /**
     * @dev Calculate voting power from a point at given timestamp
     * @dev Applies the linear decay formula: voting_power = bias - slope * dt
     */
    function getVotesFromEpoch(Checkpoints.Point memory point, uint256 timestamp) internal pure returns (uint256) {
        if (point.updatedAt == 0) return 0;
        
        int128 dt = int128(int256(timestamp - point.updatedAt));
        int128 bias = point.bias - point.slope * dt;
        
        if (bias < 0) bias = 0;
        
        return uint256(uint128(bias));
    }

    /**
     * @dev Calculate voting power for an account at current timestamp
     */
    function getVotes(
        Checkpoints.UserCheckpointStorage storage userStorage,
        address account
    ) internal view returns (uint256) {
        uint256 epoch = userStorage.userPointEpoch[account];
        return getVotesFromEpoch(userStorage, account, epoch, block.timestamp);
    }

    /**
     * @dev Calculate voting power for an account at a specific timestamp
     */
    function getPastVotes(
        Checkpoints.UserCheckpointStorage storage userStorage,
        address account,
        uint256 timepoint
    ) internal view returns (uint256) {
        uint256 epoch = Checkpoints.findUserTimestampEpoch(userStorage, account, timepoint);
        return getVotesFromEpoch(userStorage, account, epoch, timepoint);
    }

    /**
     * @dev Internal function to get voting power for an account at a specific epoch and timestamp
     * @dev This is a direct extraction of the existing _getVotesFromEpoch logic
     */
    function getVotesFromEpoch(
        Checkpoints.UserCheckpointStorage storage userStorage,
        address account,
        uint256 epoch,
        uint256 timestamp
    ) private view returns (uint256) {
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        return getVotesFromEpoch(point, timestamp);
    }

    /**
     * @dev Calculate total voting power at current timestamp
     */
    function getTotalSupply(
        Checkpoints.GlobalCheckpointStorage storage globalStorage
    ) internal view returns (uint256) {
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        if (globalEpoch == 0) return 0;
        
        Checkpoints.Point memory lastPoint = globalStorage.globalPointHistory[globalEpoch];
        return getVotesFromEpoch(lastPoint, block.timestamp);
    }

    /**
     * @dev Calculate total voting power at a specific timestamp
     * @dev Walks through historical checkpoints applying slope changes to get accurate total supply
     */
    function getPastTotalSupply(
        Checkpoints.GlobalCheckpointStorage storage globalStorage,
        uint256 timepoint
    ) internal view returns (uint256) {
        uint256 epoch = Checkpoints.findTimestampEpoch(globalStorage, timepoint);
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory lastPoint = globalStorage.globalPointHistory[epoch];
        
        // Move forward from the found point to the target timestamp
        // applying any scheduled global slope changes along the way.
        uint256 currentTimestamp = Checkpoints.timestampFloorToWeek(lastPoint.updatedAt);
        for (uint256 i = 0; i < 255; i++) {
            currentTimestamp += Constants.WEEK;
            int128 d_slope = 0;
            
            if (currentTimestamp > timepoint) {
                currentTimestamp = timepoint;
            } else {
                d_slope = globalStorage.slopeChanges[currentTimestamp];
            }
            
            // Calculate bias decay to currentTimestamp
            lastPoint.bias -= lastPoint.slope * int128(int256(currentTimestamp - lastPoint.updatedAt));
            
            if (currentTimestamp == timepoint) {
                break;
            }
            
            // Apply slope change at week boundary
            lastPoint.slope += d_slope;
            lastPoint.updatedAt = currentTimestamp;
        }
        
        // Ensure non-negative
        if (lastPoint.bias < 0) lastPoint.bias = 0;
        
        return uint256(uint128(lastPoint.bias));
    }

}