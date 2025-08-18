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
    ) internal view returns (uint256) {
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        return Checkpoints.getVotesFromEpoch(point, timestamp);
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
        return Checkpoints.getVotesFromEpoch(lastPoint, block.timestamp);
    }

    /**
     * @dev Calculate total voting power at a specific timestamp
     * @dev Direct extraction of existing getPastTotalSupply logic
     */
    function getPastTotalSupply(
        Checkpoints.GlobalCheckpointStorage storage globalStorage,
        uint256 timepoint
    ) internal view returns (uint256) {
        return Checkpoints.getPastTotalSupply(globalStorage, timepoint);
    }

}