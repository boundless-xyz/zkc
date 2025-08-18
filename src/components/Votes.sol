// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotes} from "../interfaces/IVotes.sol";
import {Clock} from "./Clock.sol";
import {Storage} from "./Storage.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {VotingPower} from "../libraries/VotingPower.sol";
import {StakeManager} from "../libraries/StakeManager.sol";

/**
 * @title Votes Component
 * @notice IVotes interface implementation for veZKC voting functionality
 * @dev This component handles all voting-related functionality using shared storage
 */
abstract contract Votes is Storage, Clock, IVotes {

    /**
     * @dev IVotes implementation - Returns voting power delegated TO this account
     */
    function getVotes(address account) public view override returns (uint256) {
        return VotingPower.getVotes(_userCheckpoints, account);
    }

    function getPastVotes(address account, uint256 timepoint) public view override returns (uint256) {
        _requirePastTimepoint(timepoint);
        return VotingPower.getPastVotes(_userCheckpoints, account, timepoint);
    }

    function getPastTotalSupply(uint256 timepoint) public view override returns (uint256) {
        _requirePastTimepoint(timepoint);
        return VotingPower.getPastTotalSupply(_globalCheckpoints, timepoint);
    }

    function delegates(address account) public view virtual override returns (address) {
        address delegatee = _delegatee[account];
        return delegatee == address(0) ? account : delegatee;
    }

    function delegate(address /*delegatee*/) public pure override {
        // TODO: Implement delegation logic
        // address account = _msgSender();
        
        // // Get both user's active positions
        // uint256 myTokenId = _userActivePosition[account];
        // uint256 delegateeTokenId = _userActivePosition[delegatee];
        
        // require(myTokenId != 0, "No active position");
        // require(delegateeTokenId != 0, "Delegatee has no active position");
        
        // Checkpoints.LockInfo memory myLock = _locks[myTokenId];
        // Checkpoints.LockInfo memory delegateeLock = _locks[delegateeTokenId];
        
        // // Extend my lock to match delegatee's lock if needed
        // if (delegateeLock.lockEnd > myLock.lockEnd) {
        //     _extendLockAndCheckpoint(myTokenId, delegateeLock.lockEnd);
        // }
        
        // _delegate(account, delegatee);
    }

    function delegateBySig(address /*_delegatee*/, uint256 /*_nonce*/, uint256 /*_expiry*/, uint8 /*_v*/, bytes32 /*_r*/, bytes32 /*_s*/)
        public
        pure
        override
    {
        revert NotImplemented();
    }

    function _delegate(address /*account*/, address /*delegatee*/) internal pure {
        // TODO: Implement delegation logic
        // address oldDelegate = delegates(account);
        // _delegatee[account] = delegatee;

        // // Checkpoint delegation change
        // _checkpointDelegation(account, oldDelegate, delegatee);

        // emit DelegateChanged(account, oldDelegate, delegatee);
        // emit DelegateVotesChanged(
        //     delegatee,
        //     getVotes(oldDelegate),
        //     getVotes(delegatee)
        // );
    }

    /**
     * @dev Handle delegation checkpointing for single NFT per user
     * @dev Direct extraction of existing _checkpointDelegation logic
     */
    function _checkpointDelegation(address /*account*/, address /*oldDelegatee*/, address /*newDelegatee*/) internal pure {
        // TODO: Implement delegation checkpointing
        // // Get the user's single active position
        // uint256 tokenId = _userActivePosition[account];
        // if (tokenId == 0) return; // No active position to delegate
        
        // Checkpoints.LockInfo memory lock = _locks[tokenId];
        // if (lock.lockEnd <= block.timestamp) return; // Expired lock has no power
        
        // // When called from _addStakeAndCheckpoint with same old and new delegatee,
        // // this is a re-checkpoint to update the delegatee with new amount
        // if (oldDelegatee == newDelegatee && oldDelegatee != address(0)) {
        //     // This is a special case: updating delegation amount after top-up
        //     // The main _checkpoint already handled updating the owner's checkpoint
        //     // So we just need to update the delegatee's checkpoint with the difference
           
        //     // TODO: skip since _checkpoint already handles it correctly?
        //     return;
        // }
        
        // // Normal delegation change: transfer power from old to new delegatee
        // // Create lock states for checkpointing
        // Checkpoints.LockInfo memory emptyLock = StakeManager.emptyLock();
        
        // // Remove from old delegatee's checkpoint
        // if (oldDelegatee != address(0) && oldDelegatee != newDelegatee) {
        //     Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, oldDelegatee, lock, emptyLock);
        // }
        
        // // Add to new delegatee's checkpoint
        // if (newDelegatee != address(0) && oldDelegatee != newDelegatee) {
        //     Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, newDelegatee, emptyLock, lock);
        // }
    }

    // Abstract functions that main contract must implement
    function _msgSender() internal view virtual returns (address);
}