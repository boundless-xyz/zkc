// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Checkpoints} from "../libraries/Checkpoints.sol";

/// @title Storage
/// @notice Shared storage base contract for veZKC components
/// @dev This contract contains all the shared state that both voting and reward components need
abstract contract Storage {
    // Custom error for nonce validation
    error InvalidAccountNonce(address account, uint256 currentNonce);

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

    /// @notice Nonces for EIP-712 signatures (shared between vote and reward delegation)
    mapping(address owner => uint256) internal _nonces;

    /// @notice Gap for future extensions in upgradeable contracts
    uint256[50] private __gap;

    /// @notice Get the current nonce for an account (for EIP-712 signatures)
    /// @param owner The address of the account to get the nonce for
    /// @return The current nonce value for the specified account
    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    /// @notice Internal function to validate and consume a nonce
    function _useNonce(address owner, uint256 nonce) internal {
        uint256 currentNonce = _nonces[owner]++;
        if (nonce != currentNonce) {
            revert InvalidAccountNonce(owner, currentNonce);
        }
    }
}
