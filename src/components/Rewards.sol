// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clock} from "./Clock.sol";
import {Storage} from "./Storage.sol";
import {IRewards} from "../interfaces/IRewards.sol";
import {RewardPower} from "../libraries/RewardPower.sol";

/// @title Rewards Component
/// @notice IRewards interface implementation for veZKC reward functionality
/// @dev This component handles all reward-related functionality using shared storage
abstract contract Rewards is Storage, Clock, IRewards {

    /// @inheritdoc IRewards
    function getStakingRewards(address account) external view override returns (uint256) {
        return RewardPower.getStakingRewards(_userCheckpoints, account);
    }

    /// @inheritdoc IRewards
    function getPastStakingRewards(address account, uint256 timepoint) external view override returns (uint256) {
        _requirePastTimepoint(timepoint);
        return RewardPower.getPastStakingRewards(_userCheckpoints, account, timepoint);
    }

    /// @inheritdoc IRewards
    function getTotalStakingRewards() external view override returns (uint256) {
        return RewardPower.getTotalStakingRewards(_globalCheckpoints);
    }

    /// @inheritdoc IRewards
    function getPastTotalStakingRewards(uint256 timepoint) external view override returns (uint256) {
        _requirePastTimepoint(timepoint);
        return RewardPower.getPastTotalStakingRewards(_globalCheckpoints, timepoint);
    }

    /// @inheritdoc IRewards
    function getPoVWRewardCap(address account) external view override returns (uint256) {
        return RewardPower.getPoVWRewardCap(_userCheckpoints, account);
    }

    /// @inheritdoc IRewards
    function getPastPoVWRewardCap(address account, uint256 timepoint) external view override returns (uint256) {
        _requirePastTimepoint(timepoint);
        return RewardPower.getPastPoVWRewardCap(_userCheckpoints, account, timepoint);
    }

    function _msgSender() internal view virtual returns (address);
}