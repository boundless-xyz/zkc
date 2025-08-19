// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "../libraries/Checkpoints.sol";

/**
 * @title Storage
 * @notice Shared storage base contract for veZKC components
 * @dev This contract contains all the shared state that both voting and reward components need
 */
abstract contract Storage {
    
    // Shared checkpoint storage used by both voting and rewards
    Checkpoints.UserCheckpointStorage internal _userCheckpoints;
    Checkpoints.GlobalCheckpointStorage internal _globalCheckpoints;
    
    // Stake and position storage
    mapping(uint256 tokenId => Checkpoints.StakeInfo) internal _stakes;
    mapping(address user => uint256 activeTokenId) internal _userActivePosition;
    
    // Delegation storage (used by voting)
    mapping(address account => address) internal _delegatee;
    
    // Token tracking for NFT management
    uint256 internal _currentTokenId;
    
    // Owned tokens tracking
    mapping(address account => uint256[]) internal _ownedTokens;
    mapping(uint256 tokenId => uint256) internal _ownedTokensIndex;
    
}