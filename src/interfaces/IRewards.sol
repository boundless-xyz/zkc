// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IRewards
/// @notice Interface for reward distribution calculations
/// @dev Used by external contracts to determine reward allocations based on stake amounts
interface IRewards {
    // Events
    event RewardDelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    
    /// @notice Get current staking rewards power for an account
    /// @param account Account to query
    /// @return Reward power (staked amount / REWARD_POWER_SCALAR)
    function getStakingRewards(address account) external view returns (uint256);
    
    /// @notice Get historical staking rewards power for an account
    /// @param account Account to query
    /// @param timepoint Historical timestamp to query
    /// @return Reward power at the specified timestamp
    function getPastStakingRewards(address account, uint256 timepoint) external view returns (uint256);
    
    /// @notice Get total staking rewards power across all users
    /// @return Total reward power
    function getTotalStakingRewards() external view returns (uint256);
    
    /// @notice Get historical total staking rewards power
    /// @param timepoint Historical timestamp to query
    /// @return Total reward power at the specified timestamp
    function getPastTotalStakingRewards(uint256 timepoint) external view returns (uint256);

    /// @notice Get current PoVW reward cap for an account
    /// @param account Account to query
    /// @return PoVW reward cap (staked amount / POVW_REWARD_CAP_SCALAR)
    function getPoVWRewardCap(address account) external view returns (uint256);
    
    /// @notice Get historical PoVW reward cap for an account
    /// @param account Account to query
    /// @param timepoint Historical timestamp to query
    /// @return PoVW reward cap at the specified timestamp
    function getPastPoVWRewardCap(address account, uint256 timepoint) external view returns (uint256);
    
    /// @notice Returns the reward delegate chosen by an account
    /// @param account Account to query
    /// @return The address that account has delegated rewards to (or account itself if none)
    function rewardDelegates(address account) external view returns (address);
    
    /// @notice Delegate reward power to another address
    /// @param delegatee Address to delegate rewards to
    function delegateRewards(address delegatee) external;
}