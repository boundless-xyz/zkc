// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Constants Library
 * @notice Shared constants used across the veZKC system
 */
library Constants {
    /// @dev Withdrawal period - 30 days
    uint256 public constant WITHDRAWAL_PERIOD = 30 days;
    
    /// @dev Voting power scalar (1 = 1:1 ratio in token units)
    /// @dev Example: 1 means 1 ZKC = 1e18 voting power (same as token decimals)
    /// @dev Example: 2 means 1 ZKC = 0.5e18 voting power  
    uint256 public constant VOTING_POWER_SCALAR = 1;
    
    /// @dev Reward power scalar (1 = 1:1 ratio in token units)
    /// @dev Example: 1 means 1 ZKC = 1e18 reward power (same as token decimals)
    /// @dev Example: 2 means 1 ZKC = 0.5e18 reward power
    uint256 public constant REWARD_POWER_SCALAR = 1;
    
    /// @dev 1 week in seconds (kept for potential future use)
    uint256 public constant WEEK = 1 weeks;
}