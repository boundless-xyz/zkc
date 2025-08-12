// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ZKC} from "./ZKC.sol";
import {veZKC} from "./veZKC.sol";

contract StakingVault is 
    Initializable,
    AccessControlUpgradeable, 
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    ZKC public zkcToken;
    veZKC public veZkcToken;

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    
    mapping(uint256 tokenId => address originalOwner) public nftOwners;

    event Staked(address indexed user, uint256 amount, uint256 indexed tokenId);
    event StakeAdded(address indexed user, uint256 indexed tokenId, uint256 addedAmount);
    event LockExtended(address indexed user, uint256 indexed tokenId);
    event Unstaked(address indexed user, uint256 indexed tokenId, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _zkcToken,
        address _veZkcToken,
        address _admin
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        zkcToken = ZKC(_zkcToken);
        veZkcToken = veZKC(_veZkcToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function stake(uint256 amount, uint256 lockWeeks) external nonReentrant returns (uint256 tokenId) {
        require(amount > 0, "Amount must be greater than 0");
        
        address user = msg.sender;
        
        // Transfer ZKC from user
        IERC20(address(zkcToken)).safeTransferFrom(user, address(this), amount);
        
        // Mint veZKC NFT with voting/reward power
        tokenId = veZkcToken.mint(user, amount, lockWeeks);
        
        // Track the original owner
        nftOwners[tokenId] = user;

        emit Staked(user, amount, tokenId);
        return tokenId;
    }

    function addToStake(uint256 tokenId, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(nftOwners[tokenId] == msg.sender, "Not the owner of this NFT");
        
        address user = msg.sender;
        
        // Check that the lock hasn't expired
        (, uint256 lockEnd,) = veZkcToken.locks(tokenId);
        require(block.timestamp < lockEnd, "Lock has expired, please unstake first");
        
        // Transfer ZKC from user
        IERC20(address(zkcToken)).safeTransferFrom(user, address(this), amount);
        
        // Add to existing veZKC position (preserves existing decay)
        veZkcToken.addStake(tokenId, amount);

        emit StakeAdded(user, tokenId, amount);
    }

    function extendLockToTime(uint256 tokenId, uint256 newLockEndTime) external nonReentrant {
        require(nftOwners[tokenId] == msg.sender, "Not the owner of this NFT");
        
        // Check that the lock hasn't expired
        (, uint256 lockEnd,) = veZkcToken.locks(tokenId);
        require(block.timestamp < lockEnd, "Lock has expired, please unstake first");
        
        // Extend the lock to new end time
        veZkcToken.extendLock(tokenId, newLockEndTime);

        emit LockExtended(msg.sender, tokenId);
    }
    
    function extendLockByWeeks(uint256 tokenId, uint256 additionalWeeks) external nonReentrant {
        require(nftOwners[tokenId] == msg.sender, "Not the owner of this NFT");
        
        // Check that the lock hasn't expired
        (, uint256 lockEnd,) = veZkcToken.locks(tokenId);
        require(block.timestamp < lockEnd, "Lock has expired, please unstake first");
        
        // Extend the lock by additional weeks
        veZkcToken.extendLockByWeeks(tokenId, additionalWeeks);

        emit LockExtended(msg.sender, tokenId);
    }
    
    // Legacy function for backward compatibility - extends by additional weeks
    function extendLock(uint256 tokenId, uint256 additionalWeeks) external nonReentrant {
        require(nftOwners[tokenId] == msg.sender, "Not the owner of this NFT");
        
        // Check that the lock hasn't expired
        (, uint256 lockEnd,) = veZkcToken.locks(tokenId);
        require(block.timestamp < lockEnd, "Lock has expired, please unstake first");
        
        // Extend the lock by additional weeks (legacy behavior)
        veZkcToken.extendLockByWeeks(tokenId, additionalWeeks);

        emit LockExtended(msg.sender, tokenId);
    }

    function unstake(uint256 tokenId) external nonReentrant {
        require(nftOwners[tokenId] == msg.sender, "Not the owner of this NFT");
        
        address user = msg.sender;
        
        // Check that the lock has expired
        (uint256 amount, uint256 lockEnd,) = veZkcToken.locks(tokenId);
        require(block.timestamp >= lockEnd, "Lock has not expired yet");
        
        // Remove NFT ownership tracking
        delete nftOwners[tokenId];
        
        // Burn the veZKC NFT
        veZkcToken.burn(tokenId);
        
        // Transfer ZKC back to user
        IERC20(address(zkcToken)).safeTransfer(user, amount);

        emit Unstaked(user, tokenId, amount);
    }

    function burnExpiredNFT(uint256 tokenId) external {
        require(nftOwners[tokenId] != address(0), "NFT does not exist or already burned");
        
        (, uint256 lockEnd,) = veZkcToken.locks(tokenId);
        require(block.timestamp >= lockEnd, "Lock has not expired yet");
        
        // Anyone can burn expired NFTs to keep the system clean
        delete nftOwners[tokenId];
        veZkcToken.burn(tokenId);
    }


    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}