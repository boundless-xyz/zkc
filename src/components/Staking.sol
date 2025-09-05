// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Storage} from "./Storage.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {StakeManager} from "../libraries/StakeManager.sol";
import {Constants} from "../libraries/Constants.sol";
import {VotingPower} from "../libraries/VotingPower.sol";
import {RewardPower} from "../libraries/RewardPower.sol";
import {ZKC} from "../ZKC.sol";
import {IVotes as OZIVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IRewards} from "../interfaces/IRewards.sol";

/// @title Staking Component
/// @notice Staking functionality for veZKC including full NFT implementation
/// @dev This component handles all staking operations and is the NFT contract
abstract contract Staking is Storage, ERC721Upgradeable, ReentrancyGuardUpgradeable, IStaking {
    ZKC internal _zkcToken;

    /// @dev Override transfers to make NFTs non-transferable (soulbound)
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0)) and burning (to == address(0))
        // But prevent regular transfers
        if (from != address(0) && to != address(0)) {
            revert NonTransferable();
        }

        return super._update(to, tokenId, auth);
    }

    /// @notice Check if contract supports a given interface
    /// @dev Implements ERC165 interface detection for IERC721 and inherited interfaces
    /// @param interfaceId The interface identifier to check
    /// @return bool True if the interface is supported
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC721).interfaceId || interfaceId == type(IStaking).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IStaking
    function stake(uint256 amount) external nonReentrant returns (uint256 tokenId) {
        return _stake(msg.sender, amount);
    }

    /// @inheritdoc IStaking
    function stakeWithPermit(uint256 amount, uint256 permitDeadline, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
        returns (uint256 tokenId)
    {
        try _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s) {} catch {}
        return _stake(msg.sender, amount);
    }

    /// @inheritdoc IStaking
    function addToStake(uint256 amount) external nonReentrant {
        uint256 tokenId = _userActivePosition[msg.sender];
        if (tokenId == 0) revert NoActivePosition();

        _addToStake(msg.sender, tokenId, amount);
    }

    /// @inheritdoc IStaking
    function addToStakeWithPermit(uint256 amount, uint256 permitDeadline, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
    {
        uint256 tokenId = _userActivePosition[msg.sender];
        if (tokenId == 0) revert NoActivePosition();

        try _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s) {} catch {}

        _addToStake(msg.sender, tokenId, amount);
    }

    /// @inheritdoc IStaking
    function addToStakeByTokenId(uint256 tokenId, uint256 amount) external nonReentrant {
        _addToStake(msg.sender, tokenId, amount);
    }

    /// @inheritdoc IStaking
    function addToStakeWithPermitByTokenId(
        uint256 tokenId,
        uint256 amount,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        try _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s) {} catch {}

        _addToStake(msg.sender, tokenId, amount);
    }

    /// @inheritdoc IStaking
    function initiateUnstake() external nonReentrant {
        // Get user's active position
        uint256 tokenId = _userActivePosition[msg.sender];
        if (tokenId == 0) revert NoActivePosition();
        if (ownerOf(tokenId) != msg.sender) revert TokenDoesNotExist();

        // Check if user has active delegations (delegating to self is allowed)
        if (_voteDelegatee[msg.sender] != address(0) && _voteDelegatee[msg.sender] != msg.sender) {
            revert MustUndelegateVotesFirst();
        }
        if (_rewardDelegatee[msg.sender] != address(0) && _rewardDelegatee[msg.sender] != msg.sender) {
            revert MustUndelegateRewardsFirst();
        }

        // Get current stake info
        Checkpoints.StakeInfo memory stakeInfo = _stakes[tokenId];

        // Validate withdrawal can be initiated
        StakeManager.validateWithdrawalInitiation(stakeInfo);

        // Mark as withdrawing and checkpoint (powers drop to 0)
        _initiateUnstakeAndCheckpoint(tokenId);
    }

    /// @inheritdoc IStaking
    function completeUnstake() external nonReentrant {
        address user = msg.sender;
        uint256 tokenId = _userActivePosition[user];

        Checkpoints.StakeInfo memory stakeInfo = _stakes[tokenId];
        StakeManager.validateUnstakeCompletion(tokenId, stakeInfo);

        // Remove user's active position tracking
        delete _userActivePosition[user];

        // Burn the veZKC NFT
        _burnStake(tokenId);

        // Transfer ZKC back to user
        StakeManager.transferTokensOut(IERC20(address(_zkcToken)), user, stakeInfo.amount);

        emit UnstakeCompleted(tokenId, user, stakeInfo.amount);
    }

    /// @inheritdoc IStaking
    function getStakedAmountAndWithdrawalTime(address account) public view returns (uint256, uint256) {
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) return (0, 0);

        Checkpoints.StakeInfo memory stakeInfo = _stakes[tokenId];
        uint256 withdrawableAt;
        if (stakeInfo.withdrawalRequestedAt > 0) {
            withdrawableAt = stakeInfo.withdrawalRequestedAt + Constants.WITHDRAWAL_PERIOD;
        }

        return (stakeInfo.amount, withdrawableAt);
    }

    /// @inheritdoc IStaking
    function getActiveTokenId(address user) public view returns (uint256) {
        return _userActivePosition[user];
    }

    function _stake(address user, uint256 amount) internal returns (uint256 tokenId) {
        StakeManager.validateStake(amount, _userActivePosition[user]);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), user, amount);

        // Mint veZKC NFT with voting/reward power
        tokenId = _stakeAndCheckpoint(user, amount);

        // Track user's active position
        _userActivePosition[user] = tokenId;

        return tokenId;
    }

    function _stakeAndCheckpoint(address to, uint256 amount) internal returns (uint256) {
        uint256 tokenId = ++_currentTokenId;
        _mint(to, tokenId);

        Checkpoints.StakeInfo memory emptyStake; // Empty stake (new mint)
        Checkpoints.StakeInfo memory newStake = StakeManager.createStake(amount);

        _stakes[tokenId] = newStake;

        // Handle delegation-aware checkpointing
        _checkpointWithDelegation(to, emptyStake, newStake);

        emit StakeCreated(tokenId, to, amount);
        return tokenId;
    }

    function _addStakeAndCheckpoint(uint256 tokenId, uint256 newAmount) internal {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        // Capture old state before modification
        Checkpoints.StakeInfo memory oldStake = _stakes[tokenId];

        // Create new stake state with added amount
        Checkpoints.StakeInfo memory newStake = StakeManager.addToStake(oldStake, newAmount);

        _stakes[tokenId] = newStake;

        address owner = ownerOf(tokenId);

        // Handle delegation-aware checkpointing
        _checkpointWithDelegation(owner, oldStake, newStake);

        emit StakeAdded(tokenId, owner, newAmount, newStake.amount);
    }

    function _initiateUnstakeAndCheckpoint(uint256 tokenId) internal {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        // Capture old state before modification
        Checkpoints.StakeInfo memory oldStake = _stakes[tokenId];

        // Create new stake state with withdrawal initiated
        Checkpoints.StakeInfo memory newStake = StakeManager.initiateWithdrawal(oldStake);

        _stakes[tokenId] = newStake;

        address owner = ownerOf(tokenId);

        // Get voting and reward power before unstaking for event emission
        uint256 votesBefore = VotingPower.getVotes(_userCheckpoints, owner);
        uint256 rewardsBefore = RewardPower.getStakingRewards(_userCheckpoints, owner);

        // When initiating unstake, reduce the user's checkpoint by their OWN stake amount
        // This preserves any delegated power they've received from others
        // The user cannot have outgoing delegations at this point (checked in initiateUnstake)
        // so oldStake.amount represents their own stake contribution
        int256 votingDelta = -int256(oldStake.amount);
        int256 rewardDelta = -int256(oldStake.amount);
        
        // Update user checkpoint by removing their own stake power
        // The user may still have delegated power from others
        Checkpoints.checkpointDelta(
            _userCheckpoints,
            _globalCheckpoints,
            owner,
            votingDelta,
            rewardDelta
        );

        // Get voting and reward power after unstaking for event emission
        uint256 votesAfter = VotingPower.getVotes(_userCheckpoints, owner);
        uint256 rewardsAfter = RewardPower.getStakingRewards(_userCheckpoints, owner);

        // Emit events showing power reduction
        emit OZIVotes.DelegateVotesChanged(owner, votesBefore, votesAfter);
        emit IRewards.DelegateRewardsChanged(owner, rewardsBefore, rewardsAfter);

        uint256 withdrawableAt = newStake.withdrawalRequestedAt + Constants.WITHDRAWAL_PERIOD;
        emit UnstakeInitiated(tokenId, owner, withdrawableAt);
    }

    function _burnStake(uint256 tokenId) internal {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        delete _stakes[tokenId];
        _burn(tokenId);

        emit StakeBurned(tokenId);
    }

    function _addToStake(address from, uint256 tokenId, uint256 amount) private {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        Checkpoints.StakeInfo memory stakeInfo = _stakes[tokenId];
        StakeManager.validateAddToStake(amount, stakeInfo);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), from, amount);

        // Add to existing veZKC position
        _addStakeAndCheckpoint(tokenId, amount);

    }

    /// @dev Handle delegation-aware checkpointing
    /// @param account The account whose stake is changing
    /// @param oldStake Old stake info before the change
    /// @param newStake New stake info after the change
    function _checkpointWithDelegation(
        address account,
        Checkpoints.StakeInfo memory oldStake,
        Checkpoints.StakeInfo memory newStake
    ) internal {
        // Get delegation states
        address voteDelegatee = _voteDelegatee[account];
        address rewardDelegatee = _rewardDelegatee[account];

        // Determine if votes/rewards are delegated to someone else
        bool isVoteDelegated = voteDelegatee != address(0) && voteDelegatee != account;
        bool isRewardDelegated = rewardDelegatee != address(0) && rewardDelegatee != account;

        // Determine the effective delegates (self if not delegated)
        address effectiveVoteDelegate = isVoteDelegated ? voteDelegatee : account;
        address effectiveRewardDelegate = isRewardDelegated ? rewardDelegatee : account;

        // Get voting and reward power before changes for event emission
        uint256 votesBefore = VotingPower.getVotes(_userCheckpoints, effectiveVoteDelegate);
        uint256 rewardsBefore = RewardPower.getStakingRewards(_userCheckpoints, effectiveRewardDelegate);

        // Use the library to handle checkpointing with delegation awareness
        (int256 votingDelta, int256 rewardDelta) = Checkpoints.checkpointWithDelegation(
            _userCheckpoints,
            _globalCheckpoints,
            account,
            oldStake,
            newStake,
            isVoteDelegated,
            isRewardDelegated
        );

        // Handle delegation updates if needed
        if (isVoteDelegated && votingDelta != 0) {
            Checkpoints.checkpointVoteDelegation(_userCheckpoints, voteDelegatee, votingDelta);
        }
        if (isRewardDelegated && rewardDelta != 0) {
            Checkpoints.checkpointRewardDelegation(_userCheckpoints, rewardDelegatee, rewardDelta);
        }

        // Get voting and reward power after changes for event emission
        uint256 votesAfter = VotingPower.getVotes(_userCheckpoints, effectiveVoteDelegate);
        uint256 rewardsAfter = RewardPower.getStakingRewards(_userCheckpoints, effectiveRewardDelegate);

        // Emit events if power actually changed (don't rely on returned deltas)
        if (votesBefore != votesAfter) {
            emit OZIVotes.DelegateVotesChanged(effectiveVoteDelegate, votesBefore, votesAfter);
        }

        if (rewardsBefore != rewardsAfter) {
            emit IRewards.DelegateRewardsChanged(effectiveRewardDelegate, rewardsBefore, rewardsAfter);
        }
    }
}
