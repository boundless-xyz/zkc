// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clock} from "./Clock.sol";
import {Storage} from "./Storage.sol";
import {IRewards} from "../interfaces/IRewards.sol";
import {IVotes} from "../interfaces/IVotes.sol";
import {RewardPower} from "../libraries/RewardPower.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";

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

    function rewardDelegates(address account) external view override returns (address) {
        address delegatee = _rewardDelegatee[account];
        return delegatee == address(0) ? account : delegatee;
    }

    function delegateRewards(address rewardCollector) external override {
        address account = _msgSender();
        
        // No position requirement for reward collector (can be any address)
        _delegateRewards(account, rewardCollector);
    }

    function delegateRewardsBySig(
        address /*rewardCollector*/,
        uint256 /*nonce*/,
        uint256 /*expiry*/,
        uint8 /*v*/,
        bytes32 /*r*/,
        bytes32 /*s*/
    ) external pure override {
        revert IVotes.NotImplemented();
    }

    function _delegateRewards(address account, address rewardCollector) internal {
        address oldCollector = _rewardDelegatee[account] == address(0) ? account : _rewardDelegatee[account];
        _rewardDelegatee[account] = rewardCollector;

        // Checkpoint reward delegation change
        _checkpointRewardDelegation(account, oldCollector, rewardCollector);

        emit RewardDelegateChanged(account, oldCollector, rewardCollector);
    }

    function _checkpointRewardDelegation(address account, address oldCollector, address newCollector) internal {
        // Get the user's single active position
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) return; // No active position to delegate
        
        Checkpoints.LockInfo memory lock = _locks[tokenId];
        
        // For rewards, we transfer the staked amount (not decaying power)
        uint256 amount = lock.amount;
        
        // Remove from old collector's checkpoint
        if (oldCollector != address(0) && oldCollector != newCollector) {
            RewardPower.removeAmount(_userCheckpoints, oldCollector, amount);
        }
        
        // Add to new collector's checkpoint
        if (newCollector != address(0) && oldCollector != newCollector) {
            RewardPower.addAmount(_userCheckpoints, newCollector, amount);
        }
        
        // Zero out delegator's reward power (they no longer collect rewards)
        if (newCollector != address(0)) {
            RewardPower.removeAmount(_userCheckpoints, account, amount);
        } else {
            // Undelegating - restore reward power to delegator
            RewardPower.addAmount(_userCheckpoints, account, amount);
        }
    }

    function _msgSender() internal view virtual returns (address);
}