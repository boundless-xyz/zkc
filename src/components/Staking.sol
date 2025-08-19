// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Storage} from "./Storage.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {StakeManager} from "../libraries/StakeManager.sol";
import {Constants} from "../libraries/Constants.sol";
import {ZKC} from "../ZKC.sol";

/**
 * @title Staking Component
 * @notice Staking functionality for veZKC including full NFT implementation
 * @dev This component handles all staking operations and is the NFT contract
 */
abstract contract Staking is Storage, ERC721Upgradeable, ReentrancyGuardUpgradeable, IStaking {

    // Reference to ZKC token (will be set in main contract)
    ZKC internal _zkcToken;

    // Events are defined in IStaking interface

    /**
     * @dev Override transfers to make NFTs non-transferable (soulbound)
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        /**
         * @dev Allow minting (from == address(0)) and burning (to == address(0))
         * @dev But prevent regular transfers
         */
        if (from != address(0) && to != address(0)) {
            revert NonTransferable();
        }

        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Upgradeable, IERC165) returns (bool) {
        return interfaceId == type(IERC721).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Stake ZKC tokens to mint veZKC NFT
     */
    function stake(uint256 amount) external nonReentrant returns (uint256 tokenId) {
        StakeManager.validateStake(amount, _userActivePosition[msg.sender]);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), msg.sender, amount);

        // Mint veZKC NFT with voting/reward power
        tokenId = _stakeAndCheckpoint(msg.sender, amount);

        // Track user's active position
        _userActivePosition[msg.sender] = tokenId;

        emit Staked(msg.sender, amount, tokenId);
        return tokenId;
    }

    function stakeWithPermit(
        uint256 amount,
        uint256 permitDeadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external nonReentrant returns (uint256 tokenId) {
        StakeManager.validateStake(amount, _userActivePosition[msg.sender]);

        // Use permit to approve tokens
        _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), msg.sender, amount);

        // Mint veZKC NFT with voting/reward power
        tokenId = _stakeAndCheckpoint(msg.sender, amount);

        // Track user's active position
        _userActivePosition[msg.sender] = tokenId;

        emit Staked(msg.sender, amount, tokenId);
        return tokenId;
    }

    /// @notice Add stake to your own active position
    function addToStake(uint256 amount) external nonReentrant {
        uint256 tokenId = _userActivePosition[msg.sender];
        if (tokenId == 0) revert NoActivePosition();
        
        _addToStake(msg.sender, tokenId, amount);
    }

    /// @notice Add stake to your own active position using permit
    function addToStakeWithPermit(
        uint256 amount,
        uint256 permitDeadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external nonReentrant {
        uint256 tokenId = _userActivePosition[msg.sender];
        if (tokenId == 0) revert NoActivePosition();

        // Use permit to approve tokens
        _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s);
        
        _addToStake(msg.sender, tokenId, amount);
    }

    /// @notice Add stake to any user's position by token ID (donation)
    function addToStakeByTokenId(uint256 tokenId, uint256 amount) external nonReentrant {
        _addToStake(msg.sender, tokenId, amount);
    }

    /// @notice Add stake to any user's position by token ID using permit (donation)
    function addToStakeWithPermitByTokenId(
        uint256 tokenId,
        uint256 amount,
        uint256 permitDeadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external nonReentrant {
        // Use permit to approve tokens
        _zkcToken.permit(msg.sender, address(this), amount, permitDeadline, v, r, s);
        
        _addToStake(msg.sender, tokenId, amount);
    }

    function initiateUnstake() external nonReentrant {
        // Get user's active position
        uint256 tokenId = _userActivePosition[msg.sender];
        if (tokenId == 0) revert NoActivePosition();
        if (ownerOf(tokenId) != msg.sender) revert TokenDoesNotExist();
        
        // Get current stake info
        Checkpoints.StakeInfo memory stakeInfo = _stakes[tokenId];
        
        // Validate withdrawal can be initiated
        StakeManager.validateWithdrawalInitiation(stakeInfo);

        // Mark as withdrawing and checkpoint (powers drop to 0)
        _initiateUnstakeAndCheckpoint(tokenId);

        emit UnstakeInitiated(msg.sender, tokenId, stakeInfo.amount);
    }

    function completeUnstake() external nonReentrant {
        address user = msg.sender;
        uint256 tokenId = _userActivePosition[user];
        
        Checkpoints.StakeInfo memory stakeInfo = _stakes[tokenId];
        StakeManager.validateUnstakeCompletion(tokenId, stakeInfo);

        // Remove user's active position tracking
        delete _userActivePosition[user];

        // Burn the veZKC NFT
        _burnStake(tokenId);

        // Transfer ZKC back to user
        StakeManager.transferTokensOut(IERC20(address(_zkcToken)), user, stakeInfo.amount);

        emit Unstaked(user, tokenId, stakeInfo.amount);
    }

    function getStakedAmountAndWithdrawalTime(address account) public view returns (uint256, uint256) {
        uint256 tokenId = _userActivePosition[account];
        if (tokenId == 0) return (0, 0);
        
        Checkpoints.StakeInfo memory stakeInfo = _stakes[tokenId];
        uint256 withdrawableAt = 0;
        if (stakeInfo.withdrawalRequestedAt > 0) {
            withdrawableAt = stakeInfo.withdrawalRequestedAt + Constants.WITHDRAWAL_PERIOD;
        }
        
        return (stakeInfo.amount, withdrawableAt);
    }

    function getActiveTokenId(address user) public view returns (uint256) {
        return _userActivePosition[user];
    }

    // ====== INTERNAL STAKING IMPLEMENTATION ======

    function _stakeAndCheckpoint(address to, uint256 amount) internal returns (uint256) {
        uint256 tokenId = ++_currentTokenId;
        _mint(to, tokenId);

        Checkpoints.StakeInfo memory emptyStake; // Empty stake (new mint)
        Checkpoints.StakeInfo memory newStake = StakeManager.createStake(amount);
        
        _stakes[tokenId] = newStake;
        
        // Create checkpoint for voting power change
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, to, emptyStake, newStake);

        emit StakeCreated(tokenId, to, amount);
        return tokenId;
    }

    function _addStakeAndCheckpoint(uint256 tokenId, uint256 newAmount) internal {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        // Capture old state before modification
        Checkpoints.StakeInfo memory oldStake = _stakes[tokenId];

        // Create new stake state with added amount
        Checkpoints.StakeInfo memory newStake = StakeManager.addToStake(oldStake, newAmount);

        _stakes[tokenId] = newStake;
        
        address owner = ownerOf(tokenId);
        
        // Create checkpoint for voting power change
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, owner, oldStake, newStake);

        emit StakeIncreased(tokenId, newAmount, newStake.amount);
    }

    function _initiateUnstakeAndCheckpoint(uint256 tokenId) internal {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        // Capture old state before modification
        Checkpoints.StakeInfo memory oldStake = _stakes[tokenId];

        // Create new stake state with withdrawal initiated
        Checkpoints.StakeInfo memory newStake = StakeManager.initiateWithdrawal(oldStake);

        _stakes[tokenId] = newStake;
        
        address owner = ownerOf(tokenId);
        
        // Create checkpoint for voting power change (powers drop to 0)
        Checkpoints.checkpoint(_userCheckpoints, _globalCheckpoints, owner, oldStake, newStake);

        emit WithdrawalInitiated(owner, tokenId, newStake.withdrawalRequestedAt);
    }

    function _burnStake(uint256 tokenId) internal {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        
        delete _stakes[tokenId];
        _burn(tokenId);

        emit StakeBurned(tokenId);
    }

    function _addToStake(address from, uint256 tokenId, uint256 amount) private {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        
        Checkpoints.StakeInfo memory stakeInfo = _stakes[tokenId];
        StakeManager.validateAddToStake(amount, stakeInfo);

        // Transfer ZKC from user
        StakeManager.transferTokensIn(IERC20(address(_zkcToken)), from, amount);

        // Add to existing veZKC position
        _addStakeAndCheckpoint(tokenId, amount);

        emit StakeAdded(from, tokenId, amount);
    }

}