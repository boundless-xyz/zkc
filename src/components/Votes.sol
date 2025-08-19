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

    function delegate(address delegatee) public override {
        address account = _msgSender();

        // Resolve current delegate (normalized: if none set, equals account)
        address currentDelegate = delegates(account);

        if (delegatee == currentDelegate) {
            // No-op
            return;
        }

        uint256 myTokenId = _userActivePosition[account];
        require(myTokenId != 0, "No active position");

        // Disallow self supplied explicitly? Allow delegate(address(0)) to undelegate.
        require(delegatee != account, "Use address(0) to clear or no-op");

        if (delegatee != address(0)) {
            // Prevent delegation cycles / chained delegation (delegatee must not itself have a delegatee)
            require(_delegatee[delegatee] == address(0), "Chained delegation not allowed");
            uint256 delegateeTokenId = _userActivePosition[delegatee];
            require(delegateeTokenId != 0, "Delegatee has no active position");

            // Effective lock end: if currently delegated, use current delegate's lock end
            uint256 effectiveLockEnd;
            if (currentDelegate != account) {
                uint256 curDelTokenId = _userActivePosition[currentDelegate];
                effectiveLockEnd = _locks[curDelTokenId].lockEnd;
            } else {
                effectiveLockEnd = _locks[myTokenId].lockEnd;
            }
            uint256 targetLockEnd = _locks[delegateeTokenId].lockEnd;
            require(effectiveLockEnd == targetLockEnd, "Lock end times must match");
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

        // Pre-change vote snapshots for involved parties
        uint256 oldDelegatePrevVotes = getVotes(oldDelegate);
        uint256 newDelegatePrevVotes = delegatee == address(0) ? 0 : getVotes(delegatee);

        _delegatee[account] = delegatee;

        // Checkpoint delegation change
        _checkpointDelegation(account, oldDelegate, delegatee);

        emit DelegateChanged(account, oldDelegate, delegatee);

        // Emit vote change events only for addresses whose vote balance actually changed
        if (oldDelegate != delegatee) {
            // Old delegate lost votes (could be the account itself if delegating away)
            uint256 oldDelegateNewVotes = getVotes(oldDelegate);
            emit DelegateVotesChanged(oldDelegate, oldDelegatePrevVotes, oldDelegateNewVotes);
            if (delegatee != address(0)) {
                uint256 newDelegateNewVotes = getVotes(delegatee);
                emit DelegateVotesChanged(delegatee, newDelegatePrevVotes, newDelegateNewVotes);
            } else {
                // Undelegating -> delegator regains votes; oldDelegate was previous delegate
                uint256 selfNewVotes = getVotes(account);
                // If oldDelegate was not the account itself, also emit for the delegator (now holder again)
                if (oldDelegate != account) {
                    // previous self votes before were 0 (since delegated away). Snapshot not taken;
                    emit DelegateVotesChanged(account, 0, selfNewVotes);
                }
            }
        }
    }

    /**
     * @dev Handle delegation checkpointing for single NFT per user
     * @dev Direct extraction of existing _checkpointDelegation logic
     */
    function _checkpointDelegation(address account, address oldDelegatee, address newDelegatee) internal {
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) return; // No active position to delegate
        
        Checkpoints.LockInfo memory delegatorLock = _locks[tokenId];
        Checkpoints.LockInfo memory emptyLock = StakeManager.emptyLock();

        bool delegateNow = (newDelegatee != address(0));
        bool wasSelf = (oldDelegatee == account);

        // inherit extended lock end when undelegating after delegatee extended past original expiry.
        if (!delegateNow && !wasSelf && delegatorLock.lockEnd <= block.timestamp) {
            uint256 oldDelTokenId = _userActivePosition[oldDelegatee];
            if (oldDelTokenId != 0) {
                uint256 extendedEnd = _locks[oldDelTokenId].lockEnd;
                if (extendedEnd > delegatorLock.lockEnd && extendedEnd > block.timestamp) {
                    _locks[tokenId].lockEnd = extendedEnd; // persist inheritance
                    delegatorLock.lockEnd = extendedEnd;   // update local copy
                }
            }
        }

        // If (effective) lock expired now, only cleanup aggregation if switching (no checkpoints required since slope=0).
        if (delegatorLock.lockEnd <= block.timestamp) {
            if (!wasSelf && delegateNow && oldDelegatee != newDelegatee && oldDelegatee != address(0)) {
                uint256 oldDelegated = _incomingDelegatedAmount[oldDelegatee];
                if (oldDelegated > 0) {
                    uint256 amt = delegatorLock.amount <= oldDelegated ? delegatorLock.amount : oldDelegated;
                    _incomingDelegatedAmount[oldDelegatee] = oldDelegated - amt;
                }
            }
            return;
        }

        // CASE DISPATCH
        // 1. Initial delegation (self -> delegatee)
        if (delegateNow && wasSelf) {
            _addDelegatedAmount(newDelegatee, delegatorLock.amount, delegatorLock.lockEnd);
            Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, account, delegatorLock, emptyLock);
            return;
        }
        // 2. Switching delegatees (delegateA -> delegateB)
        if (delegateNow && !wasSelf && oldDelegatee != newDelegatee) {
            _removeDelegatedAmount(oldDelegatee, delegatorLock.amount, delegatorLock.lockEnd);
            _addDelegatedAmount(newDelegatee, delegatorLock.amount, delegatorLock.lockEnd);
            return;
        }
        // 3. Clearing delegation (delegatee -> self)
        if (!delegateNow && !wasSelf) {
            _removeDelegatedAmount(oldDelegatee, delegatorLock.amount, delegatorLock.lockEnd);
            Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, account, emptyLock, delegatorLock);
            return;
        }
    }

    /**
     * @dev Called by staking logic when a delegatee extends its own lockEnd so that
     *      aggregated delegated voting power inherits the longer remaining time.
     * @param delegatee The account whose intrinsic lock was extended
     * @param oldLock The previous intrinsic lock (pre-extension)
     * @param newLock The updated intrinsic lock (post-extension)
     * @param delegatedAmount Total amount delegated to this delegatee that must have slope recomputed
     */
    function _onDelegateeLockExtended(
        address delegatee,
        Checkpoints.LockInfo memory oldLock,
        Checkpoints.LockInfo memory newLock,
        uint256 delegatedAmount
    ) internal {
        if (delegatedAmount == 0) return; // Nothing delegated; staking already checkpointed intrinsic part
        // Build synthetic combined locks: old = intrinsic(old) + delegated; new = intrinsic(new) + delegated
        Checkpoints.LockInfo memory oldCombined = Checkpoints.LockInfo({amount: oldLock.amount + delegatedAmount, lockEnd: oldLock.lockEnd});
        Checkpoints.LockInfo memory newCombined = Checkpoints.LockInfo({amount: newLock.amount + delegatedAmount, lockEnd: newLock.lockEnd});
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, delegatee, oldCombined, newCombined);
    }
    
    /**
     * @dev Add delegated amount to delegatee's voting power using synthetic lock
     */
    function _addDelegatedAmount(address delegatee, uint256 amount, uint256 /*lockEnd*/) private {
        uint256 delegateeTokenId = _userActivePosition[delegatee];
        require(delegateeTokenId != 0, "Delegatee has no position");
        
        Checkpoints.LockInfo memory delegateeLock = _locks[delegateeTokenId];

        // Track aggregate delegated amount
        uint256 oldDelegated = _incomingDelegatedAmount[delegatee];
        _incomingDelegatedAmount[delegatee] = oldDelegated + amount;
        
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

        uint256 oldDelegated = _incomingDelegatedAmount[delegatee];
        if (amount > oldDelegated) {
            amount = oldDelegated; // safety cap
        }
        uint256 newDelegated = oldDelegated - amount;
        _incomingDelegatedAmount[delegatee] = newDelegated;
        
        // Get delegatee's current total amount from their latest checkpoint
        uint256 delegateeEpoch = _userCheckpoints.userPointEpoch[delegatee];
        uint256 currentTotalAmount = delegateeLock.amount; // Default to intrinsic amount
        
        if (delegateeEpoch > 0) {
            Checkpoints.Point memory latestPoint = _userCheckpoints.userPointHistory[delegatee][delegateeEpoch];
            currentTotalAmount = latestPoint.amount; // Use current total (includes existing delegations)
        }
        
        // Create synthetic locks for checkpoint calculation
        Checkpoints.LockInfo memory oldCombinedLock = Checkpoints.LockInfo({amount: currentTotalAmount, lockEnd: delegateeLock.lockEnd});
        uint256 reduced = currentTotalAmount >= amount ? currentTotalAmount - amount : 0;
        Checkpoints.LockInfo memory newCombinedLock = Checkpoints.LockInfo({amount: reduced, lockEnd: delegateeLock.lockEnd});
        
        // Update delegatee's checkpoint with reduced amounts
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, delegatee, oldCombinedLock, newCombinedLock);
    }

    // Abstract functions that main contract must implement
    function _msgSender() internal view virtual returns (address);
}