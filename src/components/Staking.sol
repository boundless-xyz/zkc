// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
import {ZKC} from "../ZKC.sol";

/// @title Staking Component
/// @notice Staking functionality for veZKC including full NFT implementation
/// @dev This component handles all staking operations and is the NFT contract
abstract contract Staking is Storage, ERC721Upgradeable, ReentrancyGuardUpgradeable, IStaking {
    // Reference to ZKC token (will be set in main contract)
    ZKC internal _zkcToken;

    // Events are defined in IStaking interface

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

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC721).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IStaking
    function stake(uint256 amount) external nonReentrant returns (uint256 tokenId) {
        StakeManager.validateStake(amount, _userActivePosition[msg.sender]);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), msg.sender, amount);

        // Mint veZKC NFT with voting/reward power
        tokenId = _stakeAndCheckpoint(msg.sender, amount);

        // Track user's active position
        _userActivePosition[msg.sender] = tokenId;

        return tokenId;
    }

    /// @inheritdoc IStaking
    function stakeWithPermit(uint256 amount, uint256 permitDeadline, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
        returns (uint256 tokenId)
    {
        StakeManager.validateStake(amount, _userActivePosition[msg.sender]);

        // Use permit to approve tokens
        _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), msg.sender, amount);

        // Mint veZKC NFT with voting/reward power
        tokenId = _stakeAndCheckpoint(msg.sender, amount);

        // Track user's active position
        _userActivePosition[msg.sender] = tokenId;

        return tokenId;
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

        // Use permit to approve tokens
        _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s);

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
        // Use permit to approve tokens
        _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s);

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

        uint256 withdrawableAt = block.timestamp + Constants.WITHDRAWAL_PERIOD;
        emit UnstakeInitiated(tokenId, msg.sender, withdrawableAt);
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
        uint256 withdrawableAt = 0;
        if (stakeInfo.withdrawalRequestedAt > 0) {
            withdrawableAt = stakeInfo.withdrawalRequestedAt + Constants.WITHDRAWAL_PERIOD;
        }

        return (stakeInfo.amount, withdrawableAt);
    }

    /// @inheritdoc IStaking
    function getActiveTokenId(address user) public view returns (uint256) {
        return _userActivePosition[user];
    }

    // Internal staking implementation

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

        // When initiating unstake, user cannot have delegations
        // So we just update their own checkpoint (powers drop to 0)
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, owner, oldStake, newStake);

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

        // Get the new total amount after adding
        Checkpoints.StakeInfo memory updatedStake = _stakes[tokenId];
        emit StakeAdded(tokenId, ownerOf(tokenId), amount, updatedStake.amount);
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
        // Calculate the change in stake amount
        int256 stakeDelta = int256(newStake.amount) - int256(oldStake.amount);

        // Get delegation states
        address voteDelegatee = _voteDelegatee[account];
        address rewardDelegatee = _rewardDelegatee[account];

        // Track whether we need to update the user's own checkpoint
        bool needUserCheckpoint = false;

        // Prepare the Point for user's own checkpoint
        Checkpoints.Point memory userOldPoint;
        Checkpoints.Point memory userNewPoint;

        // Handle vote delegation
        if (voteDelegatee != address(0) && voteDelegatee != account) {
            // Votes are delegated - update delegatee's checkpoint
            Checkpoints.checkpointVoteDelegation(_userCheckpoints, voteDelegatee, stakeDelta);
        } else {
            // Votes are not delegated - will be included in user's own checkpoint
            needUserCheckpoint = true;
            if (oldStake.amount > 0) {
                userOldPoint.votingAmount = oldStake.amount;
            }
            if (newStake.amount > 0) {
                userNewPoint.votingAmount = newStake.amount;
            }
        }

        // Handle reward delegation
        if (rewardDelegatee != address(0) && rewardDelegatee != account) {
            // Rewards are delegated - update delegatee's checkpoint
            Checkpoints.checkpointRewardDelegation(_userCheckpoints, rewardDelegatee, stakeDelta);
        } else {
            // Rewards are not delegated - will be included in user's own checkpoint
            needUserCheckpoint = true;
            if (oldStake.amount > 0) {
                userOldPoint.rewardAmount = oldStake.amount;
            }
            if (newStake.amount > 0) {
                userNewPoint.rewardAmount = newStake.amount;
            }
        }

        // If either votes or rewards are not delegated, update user's checkpoint
        if (needUserCheckpoint) {
            // Set common fields
            userOldPoint.updatedAt = block.timestamp;
            userOldPoint.withdrawing = oldStake.withdrawalRequestedAt > 0;
            userNewPoint.updatedAt = block.timestamp;
            userNewPoint.withdrawing = newStake.withdrawalRequestedAt > 0;

            // Update user checkpoint
            uint256 userEpoch = _userCheckpoints.userPointEpoch[account] + 1;
            _userCheckpoints.userPointEpoch[account] = userEpoch;
            _userCheckpoints.userPointHistory[account][userEpoch] = userNewPoint;
        }

        // Always update global totals
        _updateGlobalCheckpoint(oldStake, newStake);
    }

    /// @dev Update global checkpoint for stake changes
    function _updateGlobalCheckpoint(Checkpoints.StakeInfo memory oldStake, Checkpoints.StakeInfo memory newStake)
        internal
    {
        // Calculate effective amounts (0 if withdrawing)
        uint256 oldEffectiveAmount = oldStake.withdrawalRequestedAt > 0 ? 0 : oldStake.amount;
        uint256 newEffectiveAmount = newStake.withdrawalRequestedAt > 0 ? 0 : newStake.amount;

        // Load current global point
        uint256 globalEpoch = _globalCheckpoints.globalPointEpoch;
        Checkpoints.Point memory lastGlobalPoint;
        if (globalEpoch > 0) {
            lastGlobalPoint = _globalCheckpoints.globalPointHistory[globalEpoch];
        }

        // Calculate new global point
        Checkpoints.Point memory newGlobalPoint = Checkpoints.Point({
            votingAmount: lastGlobalPoint.votingAmount + newEffectiveAmount - oldEffectiveAmount,
            rewardAmount: lastGlobalPoint.rewardAmount + newEffectiveAmount - oldEffectiveAmount,
            updatedAt: block.timestamp,
            withdrawing: false
        });

        // Update global checkpoint
        if (globalEpoch > 0 && lastGlobalPoint.updatedAt == block.timestamp) {
            // Update existing point at this timestamp
            _globalCheckpoints.globalPointHistory[globalEpoch] = newGlobalPoint;
        } else {
            // Create new global point
            globalEpoch += 1;
            _globalCheckpoints.globalPointHistory[globalEpoch] = newGlobalPoint;
            _globalCheckpoints.globalPointEpoch = globalEpoch;
        }
    }
}
