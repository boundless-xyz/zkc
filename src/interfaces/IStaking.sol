// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";

/**
 * @title IStaking
 * @notice Interface for veZKC staking functionality
 * @dev This interface defines the core staking operations for the veZKC system
 */
interface IStaking is IERC721 {
    
    // Custom errors
    error ZeroAmount();
    error UserAlreadyHasActivePosition();
    error NoActivePosition();
    error TokenDoesNotExist();
    error CannotAddToExpiredPosition();
    error LockHasNotExpiredYet();
    error NonTransferable();
    error CannotExtendLockWhileDelegated();
    error CanOnlyIncreaseLockEndTime();
    error LockCannotExceedMaxTime();
    error NewLockEndMustBeInFuture();
    
    // Events
    event Staked(address indexed user, uint256 amount, uint256 indexed tokenId);
    event StakeAdded(address indexed user, uint256 indexed tokenId, uint256 addedAmount);
    event Unstaked(address indexed user, uint256 indexed tokenId, uint256 amount);
    event LockCreated(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event LockIncreased(uint256 indexed tokenId, uint256 addedAmount, uint256 newTotal);
    event LockExtended(uint256 indexed tokenId, uint256 newLockEnd);
    event LockExpired(uint256 indexed tokenId);
    
    /**
     * @notice Stake ZKC tokens to mint veZKC NFT
     * @param amount Amount of ZKC to stake
     * @param expires Lock expiry timestamp (0 for min, type(uint256).max for max)
     * @return tokenId The minted veZKC NFT token ID
     */
    function stake(uint256 amount, uint256 expires) external returns (uint256 tokenId);
    
    /**
     * @notice Stake ZKC tokens using permit to avoid pre-approval
     * @param amount Amount of ZKC to stake
     * @param expires Lock expiry timestamp
     * @param permitDeadline Permit deadline
     * @param v Permit signature v
     * @param r Permit signature r
     * @param s Permit signature s
     * @return tokenId The minted veZKC NFT token ID
     */
    function stakeWithPermit(
        uint256 amount, 
        uint256 expires,
        uint256 permitDeadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns (uint256 tokenId);
    
    /**
     * @notice Add stake to your own active position
     * @param amount Amount of ZKC to add
     */
    function addToStake(uint256 amount) external;
    
    /**
     * @notice Add stake to your own active position using permit
     * @param amount Amount of ZKC to add
     * @param permitDeadline Permit deadline
     * @param v Permit signature v
     * @param r Permit signature r
     * @param s Permit signature s
     */
    function addToStakeWithPermit(
        uint256 amount,
        uint256 permitDeadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external;
    
    /**
     * @notice Add stake to any user's position by token ID (donation)
     * @param tokenId Token ID to add stake to
     * @param amount Amount of ZKC to add
     */
    function addToStakeByTokenId(uint256 tokenId, uint256 amount) external;
    
    /**
     * @notice Add stake to any user's position by token ID using permit
     * @param tokenId Token ID to add stake to
     * @param amount Amount of ZKC to add
     * @param permitDeadline Permit deadline
     * @param v Permit signature v
     * @param r Permit signature r
     * @param s Permit signature s
     */
    function addToStakeWithPermitByTokenId(
        uint256 tokenId,
        uint256 amount,
        uint256 permitDeadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external;
    
    /**
     * @notice Extend lock duration for your active position
     * @param newLockEndTime New lock end timestamp
     */
    function extendStakeLockup(uint256 newLockEndTime) external;
    
    /**
     * @notice Unstake ZKC tokens after lock expiry
     */
    function unstake() external;
    
    /**
     * @notice Get staked amount and expiry for an account
     * @param account Account to query
     * @return amount Staked amount
     * @return expiry Lock expiry timestamp
     */
    function getStakedAmountAndExpiry(address account) external view returns (uint256 amount, uint256 expiry);
    
    /**
     * @notice Get active token ID for a user
     * @param user User to query
     * @return tokenId Active token ID (0 if none)
     */
    function getActiveTokenId(address user) external view returns (uint256 tokenId);
}