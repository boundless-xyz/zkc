// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotes} from "../interfaces/IVotes.sol";
import {Clock} from "./Clock.sol";
import {Storage} from "./Storage.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {VotingPower} from "../libraries/VotingPower.sol";
import {StakeManager} from "../libraries/StakeManager.sol";
import {console} from "forge-std/console.sol";

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

    function delegate(address delegatee) public override {
        address account = _msgSender();
        
        // Get both user's active positions
        uint256 myTokenId = _userActivePosition[account];
        require(myTokenId != 0, "No active position");
        
        if (delegatee != address(0)) {
            uint256 delegateeTokenId = _userActivePosition[delegatee];
            require(delegateeTokenId != 0, "Delegatee has no active position");
            
            Checkpoints.LockInfo memory myLock = _locks[myTokenId];
            Checkpoints.LockInfo memory delegateeLock = _locks[delegateeTokenId];
            
            // Require delegator's lock matches delegatee's lock end time exactly
            require(myLock.lockEnd == delegateeLock.lockEnd, "Lock end times must match");
        }
        
        _delegate(account, delegatee);
    }

    function delegateBySig(address /*_delegatee*/, uint256 /*_nonce*/, uint256 /*_expiry*/, uint8 /*_v*/, bytes32 /*_r*/, bytes32 /*_s*/)
        public
        pure
        override
    {
        revert NotImplemented();
    }

    function _delegate(address account, address delegatee) internal {
        address oldDelegate = delegates(account);
        _delegatee[account] = delegatee;

        // Checkpoint delegation change
        _checkpointDelegation(account, oldDelegate, delegatee);

        emit DelegateChanged(account, oldDelegate, delegatee);
        emit DelegateVotesChanged(
            oldDelegate,
            getVotes(oldDelegate),
            getVotes(oldDelegate)
        );
        emit DelegateVotesChanged(
            delegatee,
            getVotes(delegatee),
            getVotes(delegatee)
        );
    }

    /**
     * @dev Handle delegation checkpointing for single NFT per user
     * @dev Direct extraction of existing _checkpointDelegation logic
     */
    function _checkpointDelegation(address account, address oldDelegatee, address newDelegatee) internal {
        // Get the user's single active position
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) return; // No active position to delegate
        
        Checkpoints.LockInfo memory delegatorLock = _locks[tokenId];
        if (delegatorLock.lockEnd <= block.timestamp) return; // Expired lock has no power
        
        console.log("account", account);
        console.log("oldDelegatee", oldDelegatee);
        console.log("newDelegatee", newDelegatee);
        console.log("delegatorLock.amount", delegatorLock.amount);
        
        // Remove from old delegatee's checkpoint using synthetic locks
        if (oldDelegatee != address(0) && oldDelegatee != account && oldDelegatee != newDelegatee) {
            console.log("remove from oldDelegatee");
            _removeDelegatedAmount(oldDelegatee, delegatorLock.amount, delegatorLock.lockEnd);
        }
        
        // Add to new delegatee's checkpoint using synthetic locks
        if (newDelegatee != address(0) && oldDelegatee != newDelegatee) {
            console.log("add to newDelegatee");
            _addDelegatedAmount(newDelegatee, delegatorLock.amount, delegatorLock.lockEnd);
        }
        
        // Zero out delegator's checkpoint (they no longer have voting power)
        if (newDelegatee != address(0)) {
            console.log("zero out delegator's checkpoint");
            Checkpoints.LockInfo memory emptyLock = StakeManager.emptyLock();
            Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, account, delegatorLock, emptyLock);
        } else {
            // Undelegating - restore power to delegator
            console.log("undelegate restore power to delegator");
            Checkpoints.LockInfo memory emptyLock = StakeManager.emptyLock();
            Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, account, emptyLock, delegatorLock);
        }
    }
    
    /**
     * @dev Add delegated amount to delegatee's voting power using synthetic lock
     */
    function _addDelegatedAmount(address delegatee, uint256 amount, uint256 /*lockEnd*/) private {
        uint256 delegateeTokenId = _userActivePosition[delegatee];
        require(delegateeTokenId != 0, "Delegatee has no position");
        
        Checkpoints.LockInfo memory delegateeLock = _locks[delegateeTokenId];
        
        // Get delegatee's current total amount from their latest checkpoint
        uint256 delegateeEpoch = _userCheckpoints.userPointEpoch[delegatee];
        uint256 currentTotalAmount = delegateeLock.amount; // Default to intrinsic amount
        
        if (delegateeEpoch > 0) {
            Checkpoints.Point memory latestPoint = _userCheckpoints.userPointHistory[delegatee][delegateeEpoch];
            currentTotalAmount = latestPoint.amount; // Use current total (includes existing delegations)
        }
        
        // Create synthetic locks for checkpoint calculation
        Checkpoints.LockInfo memory oldCombinedLock = Checkpoints.LockInfo({
            amount: currentTotalAmount, // Current total amount
            lockEnd: delegateeLock.lockEnd
        });
        
        Checkpoints.LockInfo memory newCombinedLock = Checkpoints.LockInfo({
            amount: currentTotalAmount + amount, // Add new delegation
            lockEnd: delegateeLock.lockEnd
        });
        
        console.log("delegatee oldAmount:", oldCombinedLock.amount);
        console.log("delegatee newAmount:", newCombinedLock.amount);
        
        // Update delegatee's checkpoint with combined amounts
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, delegatee, oldCombinedLock, newCombinedLock);
    }
    
    /**
     * @dev Remove delegated amount from delegatee's voting power using synthetic lock
     */
    function _removeDelegatedAmount(address delegatee, uint256 amount, uint256 /*lockEnd*/) private {
        uint256 delegateeTokenId = _userActivePosition[delegatee];
        if (delegateeTokenId == 0) return; // Delegatee no longer has position
        
        Checkpoints.LockInfo memory delegateeLock = _locks[delegateeTokenId];
        
        // Get delegatee's current total amount from their latest checkpoint
        uint256 delegateeEpoch = _userCheckpoints.userPointEpoch[delegatee];
        uint256 currentTotalAmount = delegateeLock.amount; // Default to intrinsic amount
        
        if (delegateeEpoch > 0) {
            Checkpoints.Point memory latestPoint = _userCheckpoints.userPointHistory[delegatee][delegateeEpoch];
            currentTotalAmount = latestPoint.amount; // Use current total (includes existing delegations)
        }
        
        // Create synthetic locks for checkpoint calculation
        Checkpoints.LockInfo memory oldCombinedLock = Checkpoints.LockInfo({
            amount: currentTotalAmount, // Current total amount
            lockEnd: delegateeLock.lockEnd
        });
        
        Checkpoints.LockInfo memory newCombinedLock = Checkpoints.LockInfo({
            amount: currentTotalAmount >= amount ? currentTotalAmount - amount : 0, // Remove delegated amount
            lockEnd: delegateeLock.lockEnd
        });
        
        console.log("delegatee remove oldAmount:", oldCombinedLock.amount);
        console.log("delegatee remove newAmount:", newCombinedLock.amount);
        
        // Update delegatee's checkpoint with reduced amounts
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, delegatee, oldCombinedLock, newCombinedLock);
    }

    // Abstract functions that main contract must implement
    function _msgSender() internal view virtual returns (address);
}