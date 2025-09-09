// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVotes} from "../interfaces/IVotes.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {Clock} from "./Clock.sol";
import {Storage} from "./Storage.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {VotingPower} from "../libraries/VotingPower.sol";
import {StakeManager} from "../libraries/StakeManager.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IVotes as OZIVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title Votes Component
/// @notice IVotes interface implementation for veZKC voting functionality
abstract contract Votes is Storage, Clock, IVotes {
    /// @dev EIP-712 type hash for vote delegation
    bytes32 private constant VOTE_DELEGATION_TYPEHASH =
        keccak256("VoteDelegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @inheritdoc OZIVotes
    function getVotes(address account) public view override returns (uint256) {
        return VotingPower.getVotes(_userCheckpoints, account);
    }

    /// @inheritdoc OZIVotes
    function getPastVotes(address account, uint256 timepoint) public view override returns (uint256) {
        _requirePastTimepoint(timepoint);
        return VotingPower.getPastVotes(_userCheckpoints, account, timepoint);
    }

    /// @inheritdoc OZIVotes
    function getPastTotalSupply(uint256 timepoint) public view override returns (uint256) {
        _requirePastTimepoint(timepoint);
        return VotingPower.getPastTotalSupply(_globalCheckpoints, timepoint);
    }

    /// @inheritdoc OZIVotes
    function delegates(address account) public view virtual override returns (address) {
        address delegatee = _voteDelegatee[account];
        return delegatee == address(0) ? account : delegatee;
    }

    /// @inheritdoc OZIVotes
    function delegate(address delegatee) public override {
        address account = _msgSender();
        _delegate(account, delegatee);
    }

    /// @inheritdoc OZIVotes
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        override
    {
        if (block.timestamp > expiry) {
            revert OZIVotes.VotesExpiredSignature(expiry);
        }

        // Create the digest for the signature
        bytes32 structHash = keccak256(abi.encode(VOTE_DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = _hashTypedDataV4(structHash);

        // Recover the signer from the signature
        address signer = ECDSA.recover(digest, v, r, s);

        // Verify and consume the nonce
        _useNonce(signer, nonce);

        // Delegate on behalf of the signer
        _delegate(signer, delegatee);
    }

    function _delegate(address account, address delegatee) internal {
        // Check if user has an active position
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) revert IStaking.NoActivePosition();

        // Check if user is withdrawing
        Checkpoints.StakeInfo memory stake = _stakes[tokenId];
        if (stake.withdrawalRequestedAt != 0) revert CannotDelegateVotesWhileWithdrawing();

        // Treat address(0) as self-delegation
        if (delegatee == address(0)) {
            delegatee = account;
        }

        address oldDelegate = delegates(account);

        // Skip if delegating to same address
        if (oldDelegate == delegatee) return;

        _voteDelegatee[account] = delegatee;

        // Get votes before changes for event emission
        uint256 oldDelegateVotesBefore = getVotes(oldDelegate);
        uint256 newDelegateVotesBefore = getVotes(delegatee);

        // Checkpoint delegation change
        _checkpointDelegation(stake, oldDelegate, delegatee);

        // Get votes after changes for event emission
        uint256 oldDelegateVotesAfter = getVotes(oldDelegate);
        uint256 newDelegateVotesAfter = getVotes(delegatee);

        emit DelegateChanged(account, oldDelegate, delegatee);

        // Emit DelegateVotesChanged for both old and new delegates
        emit DelegateVotesChanged(oldDelegate, oldDelegateVotesBefore, oldDelegateVotesAfter);
        emit DelegateVotesChanged(delegatee, newDelegateVotesBefore, newDelegateVotesAfter);
    }

    function _checkpointDelegation(Checkpoints.StakeInfo memory stake, address oldDelegatee, address newDelegatee)
        internal
    {
        // Skip if delegating to same address (this should already be checked by caller)
        if (oldDelegatee == newDelegatee) return;

        int256 votingDelta = int256(stake.amount);

        // Remove voting power from old delegatee
        Checkpoints.checkpointVoteDelegation(_userCheckpoints, oldDelegatee, -votingDelta);

        // Add voting power to new delegatee
        Checkpoints.checkpointVoteDelegation(_userCheckpoints, newDelegatee, votingDelta);
    }

    // Abstract functions that main contract must implement
    function _msgSender() internal view virtual returns (address);
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32);
}
