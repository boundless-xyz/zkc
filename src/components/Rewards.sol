// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clock} from "./Clock.sol";
import {Storage} from "./Storage.sol";
import {IRewards} from "../interfaces/IRewards.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {IVotes} from "../interfaces/IVotes.sol";
import {RewardPower} from "../libraries/RewardPower.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";

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
    
    /// @inheritdoc IRewards
    function rewardDelegates(address account) public view override returns (address) {
        address delegatee = _rewardDelegatee[account];
        return delegatee == address(0) ? account : delegatee;
    }
    
    /// @inheritdoc IRewards
    function delegateRewards(address delegatee) public override {
        address account = _msgSender();
        _delegateRewards(account, delegatee);
    }
    
    /// @dev Internal function to handle reward delegation
    function _delegateRewards(address account, address delegatee) internal {
        // Check if user has an active position
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) revert IStaking.NoActivePosition();
        
        // Check if user is withdrawing
        Checkpoints.StakeInfo memory stake = _stakes[tokenId];
        if (stake.withdrawalRequestedAt != 0) revert IVotes.CannotDelegateWhileWithdrawing();
        
        // Treat address(0) as self-delegation
        if (delegatee == address(0)) {
            delegatee = account;
        }
        
        address oldDelegate = rewardDelegates(account);
        _rewardDelegatee[account] = delegatee;
        
        // Checkpoint delegation change for rewards
        _checkpointRewardDelegation(account, oldDelegate, delegatee);
        
        emit RewardDelegateChanged(account, oldDelegate, delegatee);
    }
    
    /// @dev Handle reward delegation checkpointing
    function _checkpointRewardDelegation(address account, address oldDelegatee, address newDelegatee) internal {
        // Get the user's single active position (already validated in _delegateRewards)
        uint256 tokenId = _userActivePosition[account];
        Checkpoints.StakeInfo memory stake = _stakes[tokenId];
        
        // Skip if delegating to same address
        if (oldDelegatee == newDelegatee) return;
        
        int256 rewardDelta = int256(stake.amount);
        
        // Remove reward power from old delegatee
        if (oldDelegatee != address(0)) {
            Checkpoints.checkpointRewardDelegation(_userCheckpoints, oldDelegatee, -rewardDelta);
        }
        
        // Add reward power to new delegatee
        if (newDelegatee != address(0)) {
            Checkpoints.checkpointRewardDelegation(_userCheckpoints, newDelegatee, rewardDelta);
        }
    }

    function _msgSender() internal view virtual returns (address);
}