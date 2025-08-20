// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";
import {Constants} from "./Constants.sol";

/// @title VotingPower Library
/// @notice Voting power calculation logic for IVotes interface implementation
/// @dev Voting power = staked_amount / VOTING_POWER_SCALAR
library VotingPower {
    /// @notice Calculate voting power from a point
    /// @dev Returns votingAmount / VOTING_POWER_SCALAR
    /// @param point The checkpoint point to calculate voting power from
    /// @return Voting power
    function getVotesFromPoint(Checkpoints.Point memory point) internal pure returns (uint256) {
        return point.votingAmount / Constants.VOTING_POWER_SCALAR;
    }

    /// @notice Calculate voting power for an account at current timestamp
    /// @param userStorage User checkpoint storage
    /// @param account Address to query
    /// @return Current voting power
    function getVotes(Checkpoints.UserCheckpointStorage storage userStorage, address account)
        internal
        view
        returns (uint256)
    {
        uint256 epoch = userStorage.userPointEpoch[account];
        if (epoch == 0) return 0;

        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        return getVotesFromPoint(point);
    }

    /// @notice Calculate voting power for an account at a specific timestamp
    /// @param userStorage User checkpoint storage
    /// @param account Address to query
    /// @param timepoint Historical timestamp
    /// @return Voting power at the specified timestamp
    function getPastVotes(Checkpoints.UserCheckpointStorage storage userStorage, address account, uint256 timepoint)
        internal
        view
        returns (uint256)
    {
        uint256 epoch = Checkpoints.findUserTimestampEpoch(userStorage, account, timepoint);
        if (epoch == 0) return 0;

        Checkpoints.Point memory point = userStorage.userPointHistory[account][epoch];
        return getVotesFromPoint(point);
    }

    /// @notice Calculate total voting power at current timestamp
    /// @param globalStorage Global checkpoint storage
    /// @return Current total voting power
    function getTotalSupply(Checkpoints.GlobalCheckpointStorage storage globalStorage)
        internal
        view
        returns (uint256)
    {
        uint256 globalEpoch = globalStorage.globalPointEpoch;
        if (globalEpoch == 0) return 0;

        Checkpoints.Point memory lastPoint = globalStorage.globalPointHistory[globalEpoch];
        return getVotesFromPoint(lastPoint);
    }

    /// @notice Calculate total voting power at a specific timestamp
    /// @param globalStorage Global checkpoint storage
    /// @param timepoint Historical timestamp
    /// @return Total voting power at the specified timestamp
    function getPastTotalSupply(Checkpoints.GlobalCheckpointStorage storage globalStorage, uint256 timepoint)
        internal
        view
        returns (uint256)
    {
        uint256 epoch = Checkpoints.findTimestampEpoch(globalStorage, timepoint);
        if (epoch == 0) return 0;

        Checkpoints.Point memory point = globalStorage.globalPointHistory[epoch];
        return getVotesFromPoint(point);
    }
}
