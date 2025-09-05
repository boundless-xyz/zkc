// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Clock} from "./Clock.sol";
import {Storage} from "./Storage.sol";
import {IRewards} from "../interfaces/IRewards.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {IVotes} from "../interfaces/IVotes.sol";
import {RewardPower} from "../libraries/RewardPower.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title Rewards Component
/// @notice IRewards interface implementation for veZKC reward functionality
/// @dev This component handles all reward-related functionality using shared storage
abstract contract Rewards is Storage, Clock, IRewards {
    /// @dev EIP-712 type hash for reward delegation
    bytes32 private constant REWARD_DELEGATION_TYPEHASH =
        keccak256("RewardDelegation(address delegatee,uint256 nonce,uint256 expiry)");
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

    /// @inheritdoc IRewards
    function delegateRewardsBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        override
    {
        if (block.timestamp > expiry) {
            revert RewardsExpiredSignature(expiry);
        }

        // Create the digest for the signature
        bytes32 structHash = keccak256(abi.encode(REWARD_DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = _hashTypedDataV4(structHash);

        // Recover the signer from the signature
        address signer = ECDSA.recover(digest, v, r, s);

        // Verify and consume the nonce (shared with vote delegation)
        _useNonce(signer, nonce);

        // Delegate rewards on behalf of the signer
        _delegateRewards(signer, delegatee);
    }

    /// @dev Internal function to handle reward delegation
    function _delegateRewards(address account, address delegatee) internal {
        // Check if user has an active position
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) revert IStaking.NoActivePosition();

        // Check if user is withdrawing
        Checkpoints.StakeInfo memory stake = _stakes[tokenId];
        if (stake.withdrawalRequestedAt != 0) revert CannotDelegateRewardsWhileWithdrawing();

        // Treat address(0) as self-delegation
        if (delegatee == address(0)) {
            delegatee = account;
        }

        address oldDelegate = rewardDelegates(account);

        // Skip if delegating to same address
        if (oldDelegate == delegatee) return;
        
        // Capture reward power before the change
        uint256 oldDelegateRewardsBefore = RewardPower.getStakingRewards(_userCheckpoints, oldDelegate);
        uint256 newDelegateRewardsBefore = RewardPower.getStakingRewards(_userCheckpoints, delegatee);
        
        _rewardDelegatee[account] = delegatee;

        // Checkpoint delegation change for rewards
        _checkpointRewardDelegation(stake, oldDelegate, delegatee);

        // Capture reward power after the change
        uint256 oldDelegateRewardsAfter = RewardPower.getStakingRewards(_userCheckpoints, oldDelegate);
        uint256 newDelegateRewardsAfter = RewardPower.getStakingRewards(_userCheckpoints, delegatee);

        emit RewardDelegateChanged(account, oldDelegate, delegatee);
        
        // Emit DelegateRewardsChanged for both old and new delegates
        emit DelegateRewardsChanged(oldDelegate, oldDelegateRewardsBefore, oldDelegateRewardsAfter);
        emit DelegateRewardsChanged(delegatee, newDelegateRewardsBefore, newDelegateRewardsAfter);
    }

    /// @dev Handle reward delegation checkpointing
    function _checkpointRewardDelegation(Checkpoints.StakeInfo memory stake, address oldDelegatee, address newDelegatee)
        internal
    {
        // Skip if delegating to same address (this should already be checked by caller)
        if (oldDelegatee == newDelegatee) return;

        int256 rewardDelta = int256(stake.amount);

        // Remove reward power from old delegatee (never address(0) due to rewardDelegates() behavior)
        Checkpoints.checkpointRewardDelegation(_userCheckpoints, oldDelegatee, -rewardDelta);

        // Add reward power to new delegatee (never address(0) due to address(0) -> account conversion)
        Checkpoints.checkpointRewardDelegation(_userCheckpoints, newDelegatee, rewardDelta);
    }

    function _msgSender() internal view virtual returns (address);
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32);
}
