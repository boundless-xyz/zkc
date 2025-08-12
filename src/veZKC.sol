// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IVotes} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IRewardPower} from "./interfaces/IRewardPower.sol";

contract veZKC is 
    Initializable,
    ERC721Upgradeable, 
    AccessControlUpgradeable, 
    UUPSUpgradeable,
    IVotes,
    IRewardPower,
    IERC6372
{
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;

    struct LockInfo {
        // Total ZKC amount locked
        uint256 amount;           
        // When the lock expires
        uint256 lockEnd;          
        // Lock duration in weeks (4-208 weeks)
        uint256 lockWeeks;        
    }

    bytes32 public constant STAKING_VAULT_ROLE = keccak256("STAKING_VAULT_ROLE");
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    
    uint256 public constant MIN_LOCK_WEEKS = 4;     // 4 weeks minimum
    uint256 public constant MAX_LOCK_WEEKS = 52;   // 1 year maximum (52 weeks)
    uint256 public constant WEEK = 1 weeks;         // 1 week in seconds
    uint256 public constant MAXTIME = MAX_LOCK_WEEKS * WEEK; // Maximum lock time
    
    uint256 private _currentTokenId;

    mapping(uint256 tokenId => LockInfo) public locks;
    mapping(address account => address) private _delegatee;
    mapping(address account => uint256) private _lastAccountVotingPower; // Track last known voting power
    mapping(address delegatee => Checkpoints.Trace208) private _delegateCheckpoints;
    Checkpoints.Trace208 private _totalCheckpoints;

    event LockCreated(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event LockIncreased(uint256 indexed tokenId, uint256 addedAmount, uint256 newTotal);
    event LockExtended(uint256 indexed tokenId, uint256 newLockEnd);
    event LockExpired(uint256 indexed tokenId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _stakingVault, address _admin) public initializer {
        __ERC721_init("Vote Escrowed ZK Coin", "veZKC");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(STAKING_VAULT_ROLE, _stakingVault);
    }

    function mint(address to, uint256 amount, uint256 lockWeeks) external onlyRole(STAKING_VAULT_ROLE) returns (uint256) {
        require(_isValidLockWeeks(lockWeeks), "Invalid lock weeks");
        
        uint256 tokenId = ++_currentTokenId;
        _mint(to, tokenId);
        
        locks[tokenId] = LockInfo({
            amount: amount,
            lockEnd: block.timestamp + (lockWeeks * WEEK),
            lockWeeks: lockWeeks
        });

        _updateVotingPower(to, tokenId);

        emit LockCreated(tokenId, to, amount);
        return tokenId;
    }

    function addStake(uint256 tokenId, uint256 newAmount) external onlyRole(STAKING_VAULT_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        LockInfo storage lock = locks[tokenId];
        require(block.timestamp < lock.lockEnd, "Lock has expired");

        // Curve approach: just add to the amount, voting power calculated based on remaining time
        lock.amount += newAmount;

        _updateVotingPower(ownerOf(tokenId), tokenId);

        emit LockIncreased(tokenId, newAmount, lock.amount);
    }

    function extendLock(uint256 tokenId, uint256 newLockEndTime) external onlyRole(STAKING_VAULT_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        LockInfo storage lock = locks[tokenId];
        require(block.timestamp < lock.lockEnd, "Lock has expired");
        
        // Round down to nearest week boundary (like Velodrome)
        uint256 roundedNewLockEnd = (newLockEndTime / WEEK) * WEEK;
        
        require(roundedNewLockEnd > lock.lockEnd, "Can only increase lock end time");
        require(roundedNewLockEnd <= block.timestamp + MAXTIME, "Lock cannot exceed max time");
        
        // Update lock end time and recalculate lock weeks
        lock.lockEnd = roundedNewLockEnd;
        lock.lockWeeks = (roundedNewLockEnd - block.timestamp) / WEEK;

        _updateVotingPower(ownerOf(tokenId), tokenId);

        emit LockExtended(tokenId, lock.lockEnd);
    }
    
    function extendLockByWeeks(uint256 tokenId, uint256 additionalWeeks) external onlyRole(STAKING_VAULT_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(additionalWeeks > 0, "Additional weeks must be positive");
        
        LockInfo storage lock = locks[tokenId];
        require(block.timestamp < lock.lockEnd, "Lock has expired");
        
        // Extend by additional weeks from current lock end
        uint256 newLockEndTime = lock.lockEnd + (additionalWeeks * WEEK);
        require(newLockEndTime <= block.timestamp + MAXTIME, "Lock cannot exceed max time");
        
        // Update lock end time and recalculate lock weeks  
        lock.lockEnd = newLockEndTime;
        lock.lockWeeks = (newLockEndTime - block.timestamp) / WEEK;

        _updateVotingPower(ownerOf(tokenId), tokenId);

        emit LockExtended(tokenId, lock.lockEnd);
    }

    function burn(uint256 tokenId) external onlyRole(STAKING_VAULT_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        address owner = ownerOf(tokenId);
        delete locks[tokenId];
        _burn(tokenId);

        _updateVotingPower(owner, 0); // Update with no specific tokenId (full recalc)

        emit LockExpired(tokenId);
    }

    function votingPower(uint256 tokenId) external view returns (uint256) {
        return _getVotingPower(tokenId);
    }

    function _getVotingPower(uint256 tokenId) internal view returns (uint256) {
        if (_ownerOf(tokenId) == address(0)) return 0;
        
        LockInfo memory lock = locks[tokenId];
        
        if (block.timestamp >= lock.lockEnd) return 0;
        
        // Curve/Velodrome formula: voting_power = (amount * remaining_time) / MAXTIME
        // This gives natural incentives without artificial multipliers
        uint256 remainingTime = lock.lockEnd - block.timestamp;
        return (lock.amount * remainingTime) / MAXTIME;
    }
    
    function _getRewardPower(uint256 tokenId) internal view returns (uint256) {
        if (_ownerOf(tokenId) == address(0)) return 0;
        
        LockInfo memory lock = locks[tokenId];
        
        if (block.timestamp >= lock.lockEnd) return 0;
        
        // Same formula as voting power for consistency
        uint256 remainingTime = lock.lockEnd - block.timestamp;
        return (lock.amount * remainingTime) / MAXTIME;
    }
    
    function _isValidLockWeeks(uint256 lockWeeks) internal pure returns (bool) {
        return lockWeeks >= MIN_LOCK_WEEKS && lockWeeks <= MAX_LOCK_WEEKS;
    }
    
    // Week-based validation and conversion functions
    function weeksToSeconds(uint256 numWeeks) public pure returns (uint256) {
        return numWeeks * WEEK;
    }
    
    function secondsToWeeks(uint256 seconds_) public pure returns (uint256) {
        return seconds_ / WEEK;
    }

    function _getAccountVotingPower(address account) internal view returns (uint256) {
        uint256 totalPower = 0;
        uint256 balance = balanceOf(account);
        
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(account, i);
            totalPower += _getVotingPower(tokenId);
        }
        
        return totalPower;
    }

    function _updateVotingPower(address account, uint256 /* tokenId */) internal {
        uint256 newVotingPower = _getAccountVotingPower(account);
        uint256 oldVotingPower = _lastAccountVotingPower[account];
        address delegatee = _delegatee[account];
        
        // Handle first-time delegation (auto-delegate to self)
        if (delegatee == address(0)) {
            delegatee = account; // Self-delegate by default
            _delegatee[account] = account;
        }
        
        // Update the delegate's checkpoint with the change in voting power
        uint256 currentDelegateVotes = _delegateCheckpoints[delegatee].latest();
        uint256 newDelegateVotes = currentDelegateVotes - oldVotingPower + newVotingPower;
        _delegateCheckpoints[delegatee].push(clock(), newDelegateVotes.toUint208());
        
        // Track the new voting power for this account
        _lastAccountVotingPower[account] = newVotingPower;
        
        // Update total supply checkpoint
        uint256 newTotal = getTotalVotes();
        _totalCheckpoints.push(clock(), newTotal.toUint208());
    }

    // IVotes implementation
    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    function getVotes(address account) public view override returns (uint256) {
        return _delegateCheckpoints[delegates(account)].latest();
    }

    function getPastVotes(address account, uint256 timepoint) public view override returns (uint256) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return _delegateCheckpoints[delegates(account)].upperLookupRecent(timepoint.toUint48());
    }

    function getTotalVotes() public view returns (uint256) {
        // Recalculate total voting power across all tokens
        uint256 total = 0;
        for (uint256 i = 1; i <= _currentTokenId; i++) {
            if (_ownerOf(i) != address(0)) {
                total += _getVotingPower(i);
            }
        }
        return total;
    }

    function getPastTotalSupply(uint256 timepoint) public view override returns (uint256) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return _totalCheckpoints.upperLookupRecent(timepoint.toUint48());
    }

    function delegates(address account) public view override returns (address) {
        address delegatee = _delegatee[account];
        return delegatee == address(0) ? account : delegatee;
    }

    function delegate(address delegatee) public override {
        address account = _msgSender();
        _delegate(account, delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        // Implementation would require EIP-712 signature verification
        // Simplified for now
        revert("Not implemented");
    }

    function _delegate(address account, address delegatee) internal {
        address oldDelegate = delegates(account);
        _delegatee[account] = delegatee;

        uint256 accountVotes = _getAccountVotingPower(account);
        
        // Update old delegate (subtract account's voting power)
        if (oldDelegate != delegatee && oldDelegate != address(0)) {
            uint256 oldDelegateVotes = _delegateCheckpoints[oldDelegate].latest();
            _delegateCheckpoints[oldDelegate].push(
                clock(), 
                (oldDelegateVotes - accountVotes).toUint208()
            );
        }

        // Update new delegate (add account's voting power)
        if (delegatee != address(0)) {
            uint256 newDelegateVotes = _delegateCheckpoints[delegatee].latest();
            _delegateCheckpoints[delegatee].push(
                clock(), 
                (newDelegateVotes + accountVotes).toUint208()
            );
        }
        
        // Update the tracked voting power for this account
        _lastAccountVotingPower[account] = accountVotes;

        emit DelegateChanged(account, oldDelegate, delegatee);
        emit DelegateVotesChanged(delegatee, 
            oldDelegate != address(0) ? _delegateCheckpoints[oldDelegate].latest() : 0,
            delegatee != address(0) ? _delegateCheckpoints[delegatee].latest() : 0
        );
    }

    // Current voting power (not checkpointed, calculated live)
    function getCurrentVotingPower(address account) external view returns (uint256) {
        return _getAccountVotingPower(account);
    }

    // IRewardPower implementation (uses reward multipliers)
    function getRewardPower(address account) external view override returns (uint256) {
        return _getAccountRewardPower(account);
    }

    function getPastRewardPower(address account, uint256 timepoint) external view override returns (uint256) {
        // For now, return current power (can be enhanced with historical tracking)
        return _getAccountRewardPower(account);
    }

    function getTotalRewardPower() external view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 1; i <= _currentTokenId; i++) {
            if (_ownerOf(i) != address(0)) {
                total += _getRewardPower(i);
            }
        }
        return total;
    }

    function getPastTotalRewardPower(uint256 timepoint) external view override returns (uint256) {
        // For now, return current total (can be enhanced with historical tracking)
        return this.getTotalRewardPower();
    }

    function _getAccountRewardPower(address account) internal view returns (uint256) {
        uint256 totalPower = 0;
        uint256 balance = balanceOf(account);
        
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(account, i);
            totalPower += _getRewardPower(tokenId);
        }
        
        return totalPower;
    }

    // Override transfers to make NFTs non-transferable (soulbound)
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Allow minting (from == address(0)) and burning (to == address(0))
        // But prevent regular transfers
        if (from != address(0) && to != address(0)) {
            revert("veZKC: Non-transferable");
        }
        
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC721Upgradeable, AccessControlUpgradeable) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }

    // Public functions to get lock information
    function getMaxVotingPower(uint256 amount) external pure returns (uint256) {
        // Maximum voting power when locked for MAXTIME
        return amount;
    }
    
    function getVotingPowerForWeeks(uint256 amount, uint256 lockWeeks) external pure returns (uint256) {
        // Calculate initial voting power for a given amount and lock weeks
        return amount * lockWeeks / MAX_LOCK_WEEKS;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    // Add missing functions for ERC721Enumerable-like functionality
    function tokenOfOwnerByIndex(address owner, uint256 index) public view returns (uint256) {
        require(index < balanceOf(owner), "Index out of bounds");
        
        uint256 count = 0;
        for (uint256 i = 1; i <= _currentTokenId; i++) {
            if (_ownerOf(i) == owner) {
                if (count == index) {
                    return i;
                }
                count++;
            }
        }
        
        revert("Token not found");
    }

    // Custom error for ERC5805
    error ERC5805FutureLookup(uint256 timepoint, uint48 clock);
}