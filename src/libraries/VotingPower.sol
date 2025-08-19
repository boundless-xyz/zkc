// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";
import {Constants} from "./Constants.sol";

/**
 * @title VotingPower Library
 * @notice Voting power calculation logic for IVotes interface implementation
 * @dev Voting power = staked_amount / VOTING_POWER_SCALAR (0 if withdrawing)
 */
library VotingPower {

    /**
     * @dev Calculate voting power from a point
     * @dev Returns amount / VOTING_POWER_SCALAR if not withdrawing, else 0
     */
    function getVotesFromPoint(Checkpoints.Point memory point) internal pure returns (uint256) {
        if (point.withdrawing) return 0;
        return point.amount / Constants.VOTING_POWER_SCALAR;
    }

    /**
     * @dev Calculate voting power for an account at current timestamp
     */
    function getVotes(
        Checkpoints.UserCheckpointStorage storage userStorage,
        address account
    ) internal view returns (uint256) {
        uint256 epoch = userStorage.userPointEpoch[account];
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        return getVotesFromPoint(point);
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
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        return getVotesFromPoint(point);
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
        return getVotesFromPoint(lastPoint);
    }

    /**
     * @dev Calculate total voting power at a specific timestamp
     */
    function getPastTotalSupply(
        Checkpoints.GlobalCheckpointStorage storage globalStorage,
        uint256 timepoint
    ) internal view returns (uint256) {
        uint256 epoch = Checkpoints.findTimestampEpoch(globalStorage, timepoint);
        if (epoch == 0) return 0;
        
        Checkpoints.Point memory point = globalStorage.globalPointHistory[epoch];
        return getVotesFromPoint(point);
    }

}