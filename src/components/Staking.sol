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
import {ZKC} from "../ZKC.sol";

/**
 * @title Staking Component
 * @notice Staking functionality for veZKC including full NFT implementation
 * @dev This component handles all staking operations and is the NFT contract
 */
abstract contract Staking is Storage, ERC721Upgradeable, ReentrancyGuardUpgradeable, IStaking {

    // Reference to ZKC token (will be set in main contract)
    ZKC internal _zkcToken;

    // Events are defined in IStaking interface

    /**
     * @dev Override transfers to make NFTs non-transferable (soulbound)
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        /**
         * @dev Allow minting (from == address(0)) and burning (to == address(0))
         * @dev But prevent regular transfers
         */
        if (from != address(0) && to != address(0)) {
            revert NonTransferable();
        }

        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Upgradeable, IERC165) returns (bool) {
        return interfaceId == type(IERC721).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Stake ZKC tokens to mint veZKC NFT
     */
    function stake(uint256 amount, uint256 expires) external nonReentrant returns (uint256 tokenId) {
        StakeManager.validateStake(amount, _userActivePosition[msg.sender]);
        
        // Get the expiry timestamp with proper week rounding and validation
        expires = StakeManager.getWeekExpiry(expires);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), msg.sender, amount);

        // Mint veZKC NFT with voting/reward power
        tokenId = _stakeAndCheckpoint(msg.sender, amount, expires);

        // Track user's active position
        _userActivePosition[msg.sender] = tokenId;

        emit Staked(msg.sender, amount, tokenId);
        return tokenId;
    }

    function stakeWithPermit(
        uint256 amount, 
        uint256 expires,
        uint256 permitDeadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external nonReentrant returns (uint256 tokenId) {
        StakeManager.validateStake(amount, _userActivePosition[msg.sender]);
        
        // Get the expiry timestamp with proper week rounding and validation
        expires = StakeManager.getWeekExpiry(expires);

        // Use permit to approve tokens
        _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), msg.sender, amount);

        // Mint veZKC NFT with voting/reward power
        tokenId = _stakeAndCheckpoint(msg.sender, amount, expires);

        // Track user's active position
        _userActivePosition[msg.sender] = tokenId;

        emit Staked(msg.sender, amount, tokenId);
        return tokenId;
    }

    /// @notice Add stake to your own active position
    function addToStake(uint256 amount) external nonReentrant {
        uint256 tokenId = _userActivePosition[msg.sender];
        if (tokenId == 0) revert NoActivePosition();
        
        _addToStake(msg.sender, tokenId, amount);
    }

    /// @notice Add stake to your own active position using permit
    function addToStakeWithPermit(
        uint256 amount,
        uint256 permitDeadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external nonReentrant {
        uint256 tokenId = _userActivePosition[msg.sender];
        if (tokenId == 0) revert NoActivePosition();

        // Use permit to approve tokens
        _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s);
        
        _addToStake(msg.sender, tokenId, amount);
    }

    /// @notice Add stake to any user's position by token ID (donation)
    function addToStakeByTokenId(uint256 tokenId, uint256 amount) external nonReentrant {
        _addToStake(msg.sender, tokenId, amount);
    }

    /// @notice Add stake to any user's position by token ID using permit (donation)
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

    function extendStakeLockup(uint256 newLockEndTime) external nonReentrant {
        // Get user's active position
        uint256 tokenId = _userActivePosition[msg.sender];
        if (tokenId == 0) revert NoActivePosition();
        if (ownerOf(tokenId) != msg.sender) revert TokenDoesNotExist();
        
        // Cannot extend if delegated to someone else
        address delegatee = delegates(msg.sender);
        if (delegatee != msg.sender) revert CannotExtendLockWhileDelegated();

        // Get current lock info
        Checkpoints.LockInfo memory lock = _locks[tokenId];
        
        // Validate and get new lock end time
        uint256 validatedNewLockEnd = StakeManager.validateLockExtension(lock, newLockEndTime);

        // Extend the lock to new end time
        _extendLockAndCheckpoint(tokenId, validatedNewLockEnd);

        emit LockExtended(tokenId, _locks[tokenId].lockEnd);
    }

    function unstake() external nonReentrant {
        address user = msg.sender;
        uint256 tokenId = _userActivePosition[user];
        
        Checkpoints.LockInfo memory lock = _locks[tokenId];
        StakeManager.validateUnstake(tokenId, lock);

        // Remove user's active position tracking
        delete _userActivePosition[user];

        // Burn the veZKC NFT
        _burnLock(tokenId);

        // Transfer ZKC back to user
        StakeManager.transferTokensOut(IERC20(address(_zkcToken)), user, lock.amount);

        emit Unstaked(user, tokenId, lock.amount);
    }

    function getStakedAmountAndExpiry(address account) public view returns (uint256, uint256) {
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) return (0, 0);
        return (_locks[tokenId].amount, _locks[tokenId].lockEnd);
    }

    function getActiveTokenId(address user) public view returns (uint256) {
        return _userActivePosition[user];
    }

    // ====== INTERNAL STAKING IMPLEMENTATION ======

    function _stakeAndCheckpoint(address to, uint256 amount, uint256 expires) internal returns (uint256) {
        uint256 tokenId = ++_currentTokenId;
        _mint(to, tokenId);

        Checkpoints.LockInfo memory emptyLock; // Empty lock (new mint)
        Checkpoints.LockInfo memory newLock = StakeManager.createLock(amount, expires);
        
        _locks[tokenId] = newLock;
        
        // Create checkpoint for voting power change
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, to, emptyLock, newLock);

        emit LockCreated(tokenId, to, amount);
        return tokenId;
    }

    function _addStakeAndCheckpoint(uint256 tokenId, uint256 newAmount) internal {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        // Capture old state before modification
        Checkpoints.LockInfo memory oldLock = _locks[tokenId];

        // Create new lock state with added amount
        Checkpoints.LockInfo memory newLock = StakeManager.addToLock(oldLock, newAmount);

        _locks[tokenId] = newLock;
        
        address owner = ownerOf(tokenId);
        
        // Handle delegation updates for stake increases
        _updateDelegationOnStakeChange(owner, oldLock, newLock);

        emit LockIncreased(tokenId, newAmount, newLock.amount);
    }

    function _extendLockAndCheckpoint(uint256 tokenId, uint256 newLockEndTime) internal {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        // Capture old state before modification
        Checkpoints.LockInfo memory oldLock = _locks[tokenId];

        // Create new lock state with extended end time
        Checkpoints.LockInfo memory newLock = StakeManager.extendLock(oldLock, newLockEndTime);

        _locks[tokenId] = newLock;
        
        address owner = ownerOf(tokenId);
        
        // Create checkpoint for voting power change
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, owner, oldLock, newLock);

        emit LockExtended(tokenId, newLock.lockEnd);
    }

    function _burnLock(uint256 tokenId) internal {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        address owner = ownerOf(tokenId);
        
        // Capture old state before modification
        Checkpoints.LockInfo memory oldLock = _locks[tokenId];
        // Empty lock (burned)
        Checkpoints.LockInfo memory emptyLock = StakeManager.emptyLock();
        
        delete _locks[tokenId];
        _burn(tokenId);
        
        // Create checkpoint for voting power change
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, owner, oldLock, emptyLock);

        emit LockExpired(tokenId);
    }

    function _addToStake(address from, uint256 tokenId, uint256 amount) private {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        
        Checkpoints.LockInfo memory lock = _locks[tokenId];
        StakeManager.validateAddToStake(amount, lock);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), from, amount);

        // Add to existing veZKC position
        _addStakeAndCheckpoint(tokenId, amount);

        emit StakeAdded(from, tokenId, amount);
    }

    /**
     * @dev Update delegation checkpoints when stake amount changes
     * @dev Handles both voting and reward delegation updates
     */
    function _updateDelegationOnStakeChange(address owner, Checkpoints.LockInfo memory oldLock, Checkpoints.LockInfo memory newLock) private {
        // Check if user has delegated voting power
        address voteDelegatee = delegates(owner);
        
        if (voteDelegatee != owner) {
            // User has delegated voting - update delegatee's power with new amounts
            uint256 delegateeTokenId = _userActivePosition[voteDelegatee];
            if (delegateeTokenId != 0) {
                Checkpoints.LockInfo memory delegateeLock = _locks[delegateeTokenId];
                
                // Get delegatee's current total amount from checkpoint
                uint256 delegateeEpoch = _userCheckpoints.userPointEpoch[voteDelegatee];
                uint256 currentTotalAmount = delegateeLock.amount;
                
                if (delegateeEpoch > 0) {
                    Checkpoints.Point memory latestPoint = _userCheckpoints.userPointHistory[voteDelegatee][delegateeEpoch];
                    currentTotalAmount = latestPoint.amount;
                }
                
                // Create synthetic locks for checkpoint update
                Checkpoints.LockInfo memory oldCombinedLock = Checkpoints.LockInfo({
                    amount: currentTotalAmount,
                    lockEnd: delegateeLock.lockEnd
                });
                
                Checkpoints.LockInfo memory newCombinedLock = Checkpoints.LockInfo({
                    amount: currentTotalAmount + (newLock.amount - oldLock.amount),
                    lockEnd: delegateeLock.lockEnd
                });
                
                // Update delegatee's checkpoint with new combined amounts
                Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, voteDelegatee, oldCombinedLock, newCombinedLock);
            }
        } else {
            // User hasn't delegated voting - update their own checkpoint
            Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, owner, oldLock, newLock);
        }
        
        // Check if user has delegated reward power
        address rewardCollector = _rewardDelegatee[owner] == address(0) ? owner : _rewardDelegatee[owner];
        
        if (rewardCollector != owner) {
            // User has delegated rewards - update collector's power
            uint256 amountDelta = newLock.amount - oldLock.amount;
            RewardPower.addAmount(_userCheckpoints, rewardCollector, amountDelta);
        } else {
            // User collects their own rewards - this is handled by the voting checkpoint above
        }
    }

}