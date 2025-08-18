// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clock} from "./Clock.sol";
import {Storage} from "./Storage.sol";
import {IRewards} from "../interfaces/IRewards.sol";
import {RewardPower} from "../libraries/RewardPower.sol";

/**
 * @title Rewards Component
 * @notice IRewards interface implementation for veZKC reward functionality
 * @dev This component handles all reward-related functionality using shared storage
 */
abstract contract Rewards is Storage, Clock, IRewards {

    /**
     * @dev IRewards implementation - Get current reward power for account
     */
    function getRewards(address account) external view override returns (uint256) {
        return RewardPower.getRewards(_userCheckpoints, account);
    }

    function getPastRewards(address account, uint256 timepoint) external view override returns (uint256) {
        _requirePastTimepoint(timepoint);
        return RewardPower.getPastRewards(_userCheckpoints, account, timepoint);
    }

    function getTotalRewards() external view override returns (uint256) {
        return RewardPower.getTotalRewards(_globalCheckpoints);
    }

    function getPastTotalRewards(uint256 timepoint) external view override returns (uint256) {
        _requirePastTimepoint(timepoint);
        return RewardPower.getPastTotalRewards(_globalCheckpoints, timepoint);
    }

    function _msgSender() internal view virtual returns (address);
}