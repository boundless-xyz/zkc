// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IZKC
/// @notice Interface for the ZKC token with epoch-based emissions
/// @dev Defines ZKC-specific functionality for epoch-based reward distribution
interface IZKC {
    
    // Events
    event PoVWRewardsClaimed(address indexed recipient, uint256 amount);
    event StakingRewardsClaimed(address indexed recipient, uint256 amount);

    // Errors
    error EpochNotEnded(uint256 epoch);
    error EpochAllocationExceeded(uint256 epoch);
    error TotalAllocationExceeded();
    error InvalidInputLength();

    /// @notice Perform initial token distribution to specified recipients
    /// @dev Only callable by designated initial minters
    /// @param recipients Array of addresses to receive tokens
    /// @param amounts Array of token amounts corresponding to each recipient
    function initialMint(address[] calldata recipients, uint256[] calldata amounts) external;

    /// @notice Mint PoVW rewards for a specific recipient
    /// @dev Only callable by addresses with POVW_MINTER_ROLE
    /// @param recipient Address to receive the minted rewards
    /// @param amount Amount of tokens to mint
    function mintPoVWRewardsForRecipient(address recipient, uint256 amount) external;

    /// @notice Mint staking rewards for a specific recipient
    /// @dev Only callable by addresses with STAKING_MINTER_ROLE
    /// @param recipient Address to receive the minted rewards
    /// @param amount Amount of tokens to mint
    function mintStakingRewardsForRecipient(address recipient, uint256 amount) external;

    /// @notice Get the total supply at the start of a specific epoch
    /// @dev ZKC is emitted at the end of each epoch, this excludes rewards for the current epoch
    /// @param epoch The epoch number (0-indexed)
    /// @return The total supply at the start of the epoch
    function getSupplyAtEpochStart(uint256 epoch) external pure returns (uint256);

    /// @notice Get the total PoVW emissions allocated up to the start of a specific epoch
    /// @dev Returns cumulative PoVW emissions from genesis to the start of the provided epoch
    /// @param epoch The epoch number
    /// @return Total PoVW emissions up to the epoch start
    function getTotalPoVWEmissionsAtEpochStart(uint256 epoch) external returns (uint256);

    /// @notice Get the total staking emissions allocated up to the start of a specific epoch
    /// @dev Returns cumulative staking emissions from genesis to the start of the provided epoch
    /// @param epoch The epoch number
    /// @return Total staking emissions up to the epoch start
    function getTotalStakingEmissionsAtEpochStart(uint256 epoch) external returns (uint256);

    /// @notice Get the total emissions for a specific epoch
    /// @dev Includes both PoVW and staking rewards
    /// @param epoch The epoch number
    /// @return Total emissions for the epoch
    function getEmissionsForEpoch(uint256 epoch) external returns (uint256);

    /// @notice Get the PoVW emissions allocated for a specific epoch
    /// @param epoch The epoch number
    /// @return PoVW emissions for the epoch
    function getPoVWEmissionsForEpoch(uint256 epoch) external returns (uint256);

    /// @notice Get the staking emissions allocated for a specific epoch
    /// @param epoch The epoch number
    /// @return Staking emissions for the epoch
    function getStakingEmissionsForEpoch(uint256 epoch) external returns (uint256);

    /// @notice Get the current epoch number
    /// @dev Calculated based on time elapsed since deployment
    /// @return The current epoch number (0-indexed)
    function getCurrentEpoch() external view returns (uint256);

    /// @notice Get the start timestamp of a specific epoch
    /// @param epoch The epoch number
    /// @return The timestamp when the epoch starts
    function getEpochStartTime(uint256 epoch) external view returns (uint256);

    /// @notice Get the end timestamp of a specific epoch
    /// @dev Returns the final timestamp at which the epoch is active
    /// @param epoch The epoch number
    /// @return The timestamp when the epoch ends
    function getEpochEndTime(uint256 epoch) external view returns (uint256);

    /// @notice Get the actual minted and claimed total supply
    /// @dev This represents tokens that have been minted to accounts
    /// @return The total amount of tokens that have been claimed
    function claimedTotalSupply() external view returns (uint256);
}