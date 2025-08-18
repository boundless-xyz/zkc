// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {VeZKCStorage} from "./VeZKCStorage.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {StakeManager} from "../libraries/StakeManager.sol";
import {ZKC} from "../ZKC.sol";

/**
 * @title Staking Component
 * @notice Staking functionality for veZKC including full NFT implementation
 * @dev This component handles all staking operations and is the NFT contract
 */
abstract contract Staking is VeZKCStorage, ERC721Upgradeable, ReentrancyGuardUpgradeable {

    // Reference to ZKC token (will be set in main contract)
    ZKC internal _zkcToken;

    // Staking events
    event Staked(address indexed user, uint256 amount, uint256 indexed tokenId);
    event StakeAdded(address indexed user, uint256 indexed tokenId, uint256 addedAmount);
    event Unstaked(address indexed user, uint256 indexed tokenId, uint256 amount);
    
    // Lock events
    event LockCreated(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event LockIncreased(uint256 indexed tokenId, uint256 addedAmount, uint256 newTotal);
    event LockExtended(uint256 indexed tokenId, uint256 newLockEnd);
    event LockExpired(uint256 indexed tokenId);

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
            revert("veZKC: Non-transferable");
        }

        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
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
        require(tokenId != 0, "No active position");
        
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
        require(tokenId != 0, "No active position");

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
        require(tokenId != 0, "No active position");
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        
        // Cannot extend if delegated to someone else
        address delegatee = delegates(msg.sender);
        require(delegatee == msg.sender, "Cannot extend lock while delegated");

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
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        // Capture old state before modification
        Checkpoints.LockInfo memory oldLock = _locks[tokenId];

        // Create new lock state with added amount
        Checkpoints.LockInfo memory newLock = StakeManager.addToLock(oldLock, newAmount);

        _locks[tokenId] = newLock;
        
        address owner = ownerOf(tokenId);
        
        // Create checkpoint for voting power change
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, owner, oldLock, newLock);

        emit LockIncreased(tokenId, newAmount, newLock.amount);
    }

    function _extendLockAndCheckpoint(uint256 tokenId, uint256 newLockEndTime) internal {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

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
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

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
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        Checkpoints.LockInfo memory lock = _locks[tokenId];
        StakeManager.validateAddToStake(amount, lock);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), from, amount);

        // Add to existing veZKC position
        _addStakeAndCheckpoint(tokenId, amount);

        emit StakeAdded(from, tokenId, amount);
    }

    // Abstract function for delegation (from Votes component)  
    function delegates(address account) public view virtual returns (address);
}