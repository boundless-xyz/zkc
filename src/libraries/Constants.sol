// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Constants Library
/// @notice Shared constants used across the veZKC system
library Constants {
    /// @notice Withdrawal period - 30 days
    uint256 public constant WITHDRAWAL_PERIOD = 30 days;

    /// @notice Voting power scalar (1 = 1:1 ratio in token units)
    /// @dev Example: 1 means 1 ZKC = 1e18 voting power (same as token decimals)
    ///      Example: 2 means 1 ZKC = 0.5e18 voting power
    uint256 public constant VOTING_POWER_SCALAR = 1;

    /// @notice Staking reward power scalar (1 = 1:1 ratio in token units)
    /// @dev Example: 1 means 1 ZKC = 1e18 reward power (same as token decimals)
    ///      Example: 2 means 1 ZKC = 0.5e18 reward power
    uint256 public constant REWARD_POWER_SCALAR = 1;

    /// @notice PoVW reward cap scalar
    /// @dev Example: 3 means 1 ZKC = 0.33 ZKC reward cap
    uint256 public constant POVW_REWARD_CAP_SCALAR = 15;

    /// @notice 1 week in seconds (kept for potential future use)
    uint256 public constant WEEK = 1 weeks;
}
