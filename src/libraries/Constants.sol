// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Constants Library
 * @notice Shared constants used across the veZKC system
 */
library Constants {
    /// @dev 4 weeks minimum
    uint256 public constant MIN_STAKE_WEEKS = 4;
    /// @dev 2 years maximum (104 weeks)
    uint256 public constant MAX_STAKE_WEEKS = 104;
    /// @dev 1 week in seconds
    uint256 public constant WEEK = 1 weeks;
    /// @dev Minimum lock time
    uint256 public constant MIN_STAKE_TIME_S = MIN_STAKE_WEEKS * WEEK;
    /// @dev Maximum lock time
    uint256 public constant MAX_STAKE_TIME_S = MAX_STAKE_WEEKS * WEEK;
    /// @dev Maximum lock time as int128
    int128 public constant iMAX_STAKE_TIME_S = int128(int256(MAX_STAKE_WEEKS * WEEK));
}