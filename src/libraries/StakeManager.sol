// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "./Checkpoints.sol";
import {Constants} from "./Constants.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title StakeManager Library
/// @notice Staking operations and withdrawal management logic
/// @dev Handles staking validation and withdrawal period logic
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

    /// @notice Create a new stake info struct
    /// @param amount Amount of ZKC to stake
    /// @return New StakeInfo with specified amount and no withdrawal
    function createStake(uint256 amount) internal pure returns (Checkpoints.StakeInfo memory) {
        return Checkpoints.StakeInfo({amount: amount, withdrawalRequestedAt: 0});
    }

    /// @notice Create a stake with added amount (top-up)
    /// @dev Only allowed for active stakes, not those with pending withdrawal
    /// @param currentStake Existing stake information
    /// @param additionalAmount Amount to add to the stake
    /// @return Updated StakeInfo with combined amount
    function addToStake(Checkpoints.StakeInfo memory currentStake, uint256 additionalAmount)
        internal
        pure
        returns (Checkpoints.StakeInfo memory)
    {
        return Checkpoints.StakeInfo({
            amount: currentStake.amount + additionalAmount,
            withdrawalRequestedAt: 0
        });
    }

    /// @notice Initiate withdrawal for a stake
    /// @param currentStake Existing stake information
    /// @return Updated StakeInfo with withdrawal timestamp set
    function initiateWithdrawal(Checkpoints.StakeInfo memory currentStake)
        internal
        view
        returns (Checkpoints.StakeInfo memory)
    {
        return Checkpoints.StakeInfo({amount: currentStake.amount, withdrawalRequestedAt: block.timestamp});
    }

    /// @notice Create an empty stake (for burning)
    /// @return Empty StakeInfo struct
    function emptyStake() internal pure returns (Checkpoints.StakeInfo memory) {
        return Checkpoints.StakeInfo({amount: 0, withdrawalRequestedAt: 0});
    }

    /// @notice Check if a stake is withdrawing
    /// @param stake Stake information to check
    /// @return True if withdrawal has been initiated
    function isWithdrawing(Checkpoints.StakeInfo memory stake) internal pure returns (bool) {
        return stake.withdrawalRequestedAt > 0;
    }

    /// @notice Check if withdrawal can be completed
    /// @param stake Stake information to check
    /// @return True if withdrawal period has passed
    function canCompleteWithdrawal(Checkpoints.StakeInfo memory stake) internal view returns (bool) {
        return isWithdrawing(stake) && block.timestamp >= stake.withdrawalRequestedAt + Constants.WITHDRAWAL_PERIOD;
    }

    /// @notice Validate staking parameters
    /// @param amount Amount to stake
    /// @param userActivePosition User's current active position (should be 0)
    function validateStake(uint256 amount, uint256 userActivePosition) internal pure {
        if (amount == 0) revert ZeroAmount();
        if (userActivePosition != 0) revert UserAlreadyHasActivePosition();
    }

    /// @notice Validate add to stake parameters
    /// @param amount Amount to add
    /// @param stake Current stake information
    function validateAddToStake(uint256 amount, Checkpoints.StakeInfo memory stake) internal pure {
        if (amount == 0) revert ZeroAmount();
        if (isWithdrawing(stake)) revert CannotAddToWithdrawingPosition();
    }

    /// @notice Validate withdrawal initiation
    /// @param stake Current stake information
    function validateWithdrawalInitiation(Checkpoints.StakeInfo memory stake) internal pure {
        if (isWithdrawing(stake)) revert WithdrawalAlreadyInitiated();
    }

    /// @notice Validate unstaking completion
    /// @param tokenId Token ID being unstaked
    /// @param stake Current stake information
    function validateUnstakeCompletion(uint256 tokenId, Checkpoints.StakeInfo memory stake) internal view {
        if (tokenId == 0) revert NoActivePosition();
        if (!isWithdrawing(stake)) revert WithdrawalNotInitiated();
        if (!canCompleteWithdrawal(stake)) revert WithdrawalPeriodNotComplete();
    }

    /// @notice Transfer ZKC tokens from user to contract
    /// @param zkcToken ZKC token contract
    /// @param from Address to transfer from
    /// @param amount Amount to transfer
    function transferTokensIn(IERC20 zkcToken, address from, uint256 amount) internal {
        zkcToken.safeTransferFrom(from, address(this), amount);
    }

    /// @notice Transfer ZKC tokens from contract to user
    /// @param zkcToken ZKC token contract
    /// @param to Address to transfer to
    /// @param amount Amount to transfer
    function transferTokensOut(IERC20 zkcToken, address to, uint256 amount) internal {
        zkcToken.safeTransfer(to, amount);
    }
}
