// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";
import {Constants} from "./Constants.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title StakeManager Library
 * @notice Combined staking operations and lock management logic
 * @dev This library handles all staking and lock-related business logic extracted from veZKC
 */
library StakeManager {
    using SafeERC20 for IERC20;

    // Custom errors (combined from staking and lock management)
    error ZeroAmount();
    error UserAlreadyHasActivePosition();
    error StakeDurationTooShort();
    error StakeDurationTooLong();
    error CannotAddToExpiredPosition();
    error NoActivePosition();
    error LockHasNotExpiredYet();
    error CanOnlyIncreaseLockEndTime();
    error LockCannotExceedMaxTime();
    error NewLockEndMustBeInFuture();

    // Events
    event LockCreated(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event LockIncreased(uint256 indexed tokenId, uint256 addedAmount, uint256 newTotal);
    event LockExtended(uint256 indexed tokenId, uint256 newLockEnd);
    event LockExpired(uint256 indexed tokenId);
    event Staked(address indexed user, uint256 amount, uint256 indexed tokenId);
    event StakeAdded(address indexed user, uint256 indexed tokenId, uint256 addedAmount);
    event Unstaked(address indexed user, uint256 indexed tokenId, uint256 amount);

    /**
     * @dev Helper function to get expiry timestamp with proper week rounding and validation
     * @dev This is a direct extraction of the existing _getWeekExpiry logic
     * @param expires The requested expiry (0 for min, type(uint256).max for max, or specific timestamp)
     * @return The validated and week-rounded expiry timestamp
     */
    function getWeekExpiry(uint256 expires) internal view returns (uint256) {
        if (expires == 0) {
            // Stake for minimum duration
            expires = Checkpoints.timestampFloorToWeek(block.timestamp + Constants.MIN_STAKE_TIME_S);
            // Only add extra week if the result is too short
            if (expires <= block.timestamp + Constants.MIN_STAKE_TIME_S) {
                expires = Checkpoints.timestampFloorToWeek(block.timestamp + Constants.MIN_STAKE_TIME_S + Constants.WEEK);
            }
        } else if (expires == type(uint256).max) {
            // Stake for maximum duration
            expires = Checkpoints.timestampFloorToWeek(block.timestamp + Constants.MAX_STAKE_TIME_S);
        } else {
            // Check that the provided stake duration is valid
            expires = Checkpoints.timestampFloorToWeek(expires);
            if (expires <= block.timestamp + Constants.MIN_STAKE_TIME_S) revert StakeDurationTooShort();
            if (expires > block.timestamp + Constants.MAX_STAKE_TIME_S) revert StakeDurationTooLong();
        }
        
        return expires;
    }


    /**
     * @dev Validate lock extension parameters
     * @dev Extracted validation logic from extendStakeLockup
     */
    function validateLockExtension(
        Checkpoints.LockInfo memory currentLock,
        uint256 newLockEndTime
    ) internal view returns (uint256) {
        uint256 roundedNewLockEnd = getWeekExpiry(newLockEndTime);
        if (roundedNewLockEnd <= currentLock.lockEnd) revert CanOnlyIncreaseLockEndTime();
        if (roundedNewLockEnd > block.timestamp + Constants.MAX_STAKE_TIME_S) revert LockCannotExceedMaxTime();
        if (roundedNewLockEnd <= block.timestamp) revert NewLockEndMustBeInFuture();
        
        return roundedNewLockEnd;
    }

    /**
     * @dev Check if a lock has expired
     */
    function isExpired(Checkpoints.LockInfo memory lock) internal view returns (bool) {
        return block.timestamp >= lock.lockEnd;
    }

    /**
     * @dev Check if a lock is active (not expired)
     */
    function isActive(Checkpoints.LockInfo memory lock) internal view returns (bool) {
        return !isExpired(lock);
    }

    /**
     * @dev Create a new lock info struct
     */
    function createLock(uint256 amount, uint256 lockEnd) internal pure returns (Checkpoints.LockInfo memory) {
        return Checkpoints.LockInfo({
            amount: amount,
            lockEnd: lockEnd
        });
    }

    /**
     * @dev Create an extended lock info struct
     */
    function extendLock(
        Checkpoints.LockInfo memory currentLock,
        uint256 newLockEnd
    ) internal pure returns (Checkpoints.LockInfo memory) {
        return Checkpoints.LockInfo({
            amount: currentLock.amount,
            lockEnd: newLockEnd
        });
    }

    /**
     * @dev Create a lock with added amount (top-up)
     */
    function addToLock(
        Checkpoints.LockInfo memory currentLock,
        uint256 additionalAmount
    ) internal pure returns (Checkpoints.LockInfo memory) {
        return Checkpoints.LockInfo({
            amount: currentLock.amount + additionalAmount,
            lockEnd: currentLock.lockEnd
        });
    }

    /**
     * @dev Create an empty lock (for burning)
     */
    function emptyLock() internal pure returns (Checkpoints.LockInfo memory) {
        return Checkpoints.LockInfo({
            amount: 0,
            lockEnd: 0
        });
    }

    // ====== STAKING OPERATIONS ======

    /**
     * @dev Validate staking parameters
     */
    function validateStake(
        uint256 amount,
        uint256 userActivePosition
    ) internal pure {
        if (amount == 0) revert ZeroAmount();
        if (userActivePosition != 0) revert UserAlreadyHasActivePosition();
    }

    /**
     * @dev Validate add to stake parameters
     */
    function validateAddToStake(
        uint256 amount,
        Checkpoints.LockInfo memory lock
    ) internal view {
        if (amount == 0) revert ZeroAmount();
        if (lock.lockEnd <= block.timestamp) revert CannotAddToExpiredPosition();
    }

    /**
     * @dev Validate unstaking parameters
     */
    function validateUnstake(
        uint256 tokenId,
        Checkpoints.LockInfo memory lock
    ) internal view {
        if (tokenId == 0) revert NoActivePosition();
        if (block.timestamp < lock.lockEnd) revert LockHasNotExpiredYet();
    }

    /**
     * @dev Transfer ZKC tokens from user to contract
     */
    function transferTokensIn(
        IERC20 zkcToken,
        address from,
        uint256 amount
    ) internal {
        zkcToken.safeTransferFrom(from, address(this), amount);
    }

    /**
     * @dev Transfer ZKC tokens from contract to user
     */
    function transferTokensOut(
        IERC20 zkcToken,
        address to,
        uint256 amount
    ) internal {
        zkcToken.safeTransfer(to, amount);
    }
}