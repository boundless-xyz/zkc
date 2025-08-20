// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "../libraries/Checkpoints.sol";

/// @title Storage
/// @notice Shared storage base contract for veZKC components
/// @dev This contract contains all the shared state that both voting and reward components need
abstract contract Storage {
    /// @notice User-specific checkpoint storage for tracking voting/reward power history
    Checkpoints.UserCheckpointStorage internal _userCheckpoints;

    /// @notice Global checkpoint storage for tracking total voting/reward power history
    Checkpoints.GlobalCheckpointStorage internal _globalCheckpoints;

    /// @notice Mapping from token ID to stake information
    mapping(uint256 tokenId => Checkpoints.StakeInfo) internal _stakes;

    /// @notice Mapping from user address to their active veZKC token ID
    mapping(address user => uint256 activeTokenId) internal _userActivePosition;

    /// @notice Mapping from account to their chosen voting delegate
    mapping(address account => address) internal _voteDelegatee;

    /// @notice Mapping from account to their chosen reward delegate
    mapping(address account => address) internal _rewardDelegatee;

    /// @notice Counter for generating unique NFT token IDs
    uint256 internal _currentTokenId;

    /// @notice Array of token IDs owned by each account (for enumeration)
    mapping(address account => uint256[]) internal _ownedTokens;

    /// @notice Mapping from token ID to its index in the owner's token list
    mapping(uint256 tokenId => uint256) internal _ownedTokensIndex;
}
