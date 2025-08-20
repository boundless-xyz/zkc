// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotes} from "../interfaces/IVotes.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {Clock} from "./Clock.sol";
import {Storage} from "./Storage.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {VotingPower} from "../libraries/VotingPower.sol";
import {StakeManager} from "../libraries/StakeManager.sol";

/// @title Votes Component
/// @notice IVotes interface implementation for veZKC voting functionality
abstract contract Votes is Storage, Clock, IVotes {
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
        address delegatee = _voteDelegatee[account];
        return delegatee == address(0) ? account : delegatee;
    }

    function delegate(address delegatee) public override {
        address account = _msgSender();
        _delegate(account, delegatee);
    }

    function delegateBySig(
        address, /*_delegatee*/
        uint256, /*_nonce*/
        uint256, /*_expiry*/
        uint8, /*_v*/
        bytes32, /*_r*/
        bytes32 /*_s*/
    ) public pure override {
        revert NotImplemented();
    }

    /// @dev Handle delegation checkpointing for single NFT per user
    function _delegate(address account, address delegatee) internal {
        // Check if user has an active position
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) revert IStaking.NoActivePosition();

        // Check if user is withdrawing
        Checkpoints.StakeInfo memory stake = _stakes[tokenId];
        if (stake.withdrawalRequestedAt != 0) revert CannotDelegateWhileWithdrawing();

        // Treat address(0) as self-delegation
        if (delegatee == address(0)) {
            delegatee = account;
        }

        address oldDelegate = delegates(account);
        _voteDelegatee[account] = delegatee;

        // Checkpoint delegation change
        _checkpointDelegation(stake, oldDelegate, delegatee);

        emit DelegateChanged(account, oldDelegate, delegatee);
        emit DelegateVotesChanged(delegatee, getVotes(oldDelegate), getVotes(delegatee));
    }

    /// @dev Handle delegation checkpointing for single NFT per user
    function _checkpointDelegation(Checkpoints.StakeInfo memory stake, address oldDelegatee, address newDelegatee) internal {
        // Skip if delegating to same address
        if (oldDelegatee == newDelegatee) return;

        int256 votingDelta = int256(stake.amount);

        // Remove voting power from old delegatee
        Checkpoints.checkpointVoteDelegation(_userCheckpoints, oldDelegatee, -votingDelta);

        // Add voting power to new delegatee
        Checkpoints.checkpointVoteDelegation(_userCheckpoints, newDelegatee, votingDelta);
    }

    // Abstract functions that main contract must implement
    function _msgSender() internal view virtual returns (address);
}
