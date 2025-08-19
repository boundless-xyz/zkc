// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";
import {Constants} from "./Constants.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title StakeManager Library
 * @notice Staking operations and withdrawal management logic
 * @dev Handles staking validation and withdrawal period logic
 */
library StakeManager {
    using SafeERC20 for IERC20;

    // Custom errors
    error ZeroAmount();
    error UserAlreadyHasActivePosition();
    error CannotAddToWithdrawingPosition();
    error NoActivePosition();
    error WithdrawalAlreadyInitiated();
    error WithdrawalNotInitiated();
    error WithdrawalPeriodNotComplete();

    // Events
    event StakeCreated(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event StakeIncreased(uint256 indexed tokenId, uint256 addedAmount, uint256 newTotal);
    event StakeBurned(uint256 indexed tokenId);
    event Staked(address indexed user, uint256 amount, uint256 indexed tokenId);
    event StakeAdded(address indexed user, uint256 indexed tokenId, uint256 addedAmount);
    event Unstaked(address indexed user, uint256 indexed tokenId, uint256 amount);
    event UnstakeInitiated(address indexed user, uint256 indexed tokenId, uint256 amount);
    event WithdrawalInitiated(address indexed user, uint256 indexed tokenId, uint256 withdrawableAt);

    /**
     * @dev Create a new stake info struct
     */
    function createStake(uint256 amount) internal pure returns (Checkpoints.StakeInfo memory) {
        return Checkpoints.StakeInfo({
            amount: amount,
            withdrawalRequestedAt: 0
        });
    }

    /**
     * @dev Create a stake with added amount (top-up)
     */
    function addToStake(
        Checkpoints.StakeInfo memory currentStake,
        uint256 additionalAmount
    ) internal pure returns (Checkpoints.StakeInfo memory) {
        return Checkpoints.StakeInfo({
            amount: currentStake.amount + additionalAmount,
            withdrawalRequestedAt: 0 // Reset withdrawal when adding stake
        });
    }

    /**
     * @dev Initiate withdrawal for a stake
     */
    function initiateWithdrawal(
        Checkpoints.StakeInfo memory currentStake
    ) internal view returns (Checkpoints.StakeInfo memory) {
        return Checkpoints.StakeInfo({
            amount: currentStake.amount,
            withdrawalRequestedAt: block.timestamp
        });
    }

    /**
     * @dev Create an empty stake (for burning)
     */
    function emptyStake() internal pure returns (Checkpoints.StakeInfo memory) {
        return Checkpoints.StakeInfo({
            amount: 0,
            withdrawalRequestedAt: 0
        });
    }

    /**
     * @dev Check if a stake is withdrawing
     */
    function isWithdrawing(Checkpoints.StakeInfo memory stake) internal pure returns (bool) {
        return stake.withdrawalRequestedAt > 0;
    }

    /**
     * @dev Check if withdrawal can be completed
     */
    function canCompleteWithdrawal(Checkpoints.StakeInfo memory stake) internal view returns (bool) {
        return isWithdrawing(stake) && 
               block.timestamp >= stake.withdrawalRequestedAt + Constants.WITHDRAWAL_PERIOD;
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
        Checkpoints.StakeInfo memory stake
    ) internal pure {
        if (amount == 0) revert ZeroAmount();
        if (isWithdrawing(stake)) revert CannotAddToWithdrawingPosition();
    }

    /**
     * @dev Validate withdrawal initiation
     */
    function validateWithdrawalInitiation(
        Checkpoints.StakeInfo memory stake
    ) internal pure {
        if (isWithdrawing(stake)) revert WithdrawalAlreadyInitiated();
    }

    /**
     * @dev Validate unstaking completion
     */
    function validateUnstakeCompletion(
        uint256 tokenId,
        Checkpoints.StakeInfo memory stake
    ) internal view {
        if (tokenId == 0) revert NoActivePosition();
        if (!isWithdrawing(stake)) revert WithdrawalNotInitiated();
        if (!canCompleteWithdrawal(stake)) revert WithdrawalPeriodNotComplete();
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