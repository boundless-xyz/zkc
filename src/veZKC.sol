// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IVotes} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {IRewards} from "./interfaces/IRewards.sol";
import {ZKC} from "./ZKC.sol";

contract veZKC is
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IVotes,
    IRewards,
    IERC6372
{
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct LockInfo {
        // Total ZKC amount locked
        uint256 amount;
        // When the lock expires
        uint256 lockEnd;
    }
    
    /**
     * @dev Point represents voting power at a specific moment that decays linearly over time
     * @dev Formula: voting_power(t) = bias - slope * (t - ts)
     * @dev This follows the standard veToken model where voting power = amount * time_remaining / max_time
     */
    struct Point {
        /// @dev Voting power at timestamp ts (y-intercept)
        int128 bias;
        /// @dev Rate of decay per second (always negative while active)
        int128 slope;
        /// @dev Timestamp when recorded
        uint256 updatedAt;
    }

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// @dev 4 weeks minimum
    uint256 public constant MIN_LOCK_WEEKS = 4;
    /// @dev 1 year maximum (52 weeks)
    uint256 public constant MAX_LOCK_WEEKS = 52;
    /// @dev 1 week in seconds
    uint256 public constant WEEK = 1 weeks;
    /// @dev Maximum lock time
    uint256 public constant MAXTIME = MAX_LOCK_WEEKS * WEEK;
    /// @dev Maximum lock time as int128
    int128 public constant iMAXTIME = int128(int256(MAX_LOCK_WEEKS * WEEK));

    uint256 private _currentTokenId;

    ZKC public zkcToken;
    mapping(address user => uint256 activeTokenId) public userActivePosition;

    mapping(uint256 tokenId => LockInfo) public locks;
    mapping(address account => address) private _delegatee;
    
    /**
     * @dev Point-based Voting Power Tracking System
     * @dev User Point History: Pre-allocated array tracking power evolution per account.
     * @dev Used as checkpoints for calculating a users power at a specific timestamp.
     * @dev - Uses pre-allocated array of 1B slots for gas optimization
     * @dev - Each Point stores bias (initial power) and slope (decay rate) at a timestamp  
     * @dev - New Points appended when: stake/unstake/delegate/extend lock
     * @dev - Enables binary search for historical queries
     * @dev - Array never shrinks, only grows via _userPointEpoch counter
     */
    mapping(address account => Point[1000000000]) private _userPointHistory;
    
    /**
     * @dev User Point Epoch: Current index in the user's point history array
     * @dev - Points to the latest valid entry in _userPointHistory[account]
     * @dev - Starts at 0 for new users, incremented with each checkpoint
     * @dev - Used as upper bound for binary search operations
     */
    mapping(address account => uint256) private _userPointEpoch;
    
    /**
     * @dev Global Point History: Protocol-wide voting power tracking
     * @dev - Uses mapping instead of pre-allocated array
     * @dev - More gas efficient since there's only one global timeline
     * @dev - Updated whenever any user's voting power changes
     */
    mapping(uint256 => Point) private _globalPointHistory;
    
    /**
     * @dev Global Epoch: Current index for global point history
     * @dev - Points to latest entry in _globalPointHistory mapping
     * @dev - Always consecutive (0,1,2,3...) enabling binary search
     */
    uint256 private _globalPointEpoch;
    
    /**
     * @dev Slope Changes: Scheduled global slope adjustments when locks expire
     * @dev Slope changes can only occur on week boundaries, since we always 
     * @dev round down lock creations/extensions to the nearest week. This simplifies the process of
     * @dev calculating the global amount of voting power at any given time. 
     * @dev It also makes groups expiries together (gas efficient)
     * @dev - Maps timestamp -> total slope delta across all users
     * @dev - When user creates lock until time T: slopeChanges[T] += user_slope
     * @dev - At time T: global slope becomes less negative (decay slows) as lock expires
     * @dev - Example: Lock 1000 tokens for 1 year, slope = -1000/year
     * @dev           At expiry: slopeChanges[expiry_time] += 1000/year (makes slope less negative)
     * @dev - Used by getTotalVotes() to accurately track global voting power decay
     */
    mapping(uint256 timestamp => int128) public slopeChanges;
    
    /**
     * @dev Track which tokenIds belong to each account
     * @dev - One account can own multiple veZKC NFTs (though we limit to 1 active position)
     * @dev - Used to aggregate voting power across all positions
     */
    mapping(address account => uint256[]) private _ownedTokens;
    mapping(uint256 tokenId => uint256) private _ownedTokensIndex;

    event LockCreated(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event LockIncreased(uint256 indexed tokenId, uint256 addedAmount, uint256 newTotal);
    event LockExtended(uint256 indexed tokenId, uint256 newLockEnd);
    event LockExpired(uint256 indexed tokenId);

    // Staking events
    event Staked(address indexed user, uint256 amount, uint256 indexed tokenId);
    event StakeAdded(address indexed user, uint256 indexed tokenId, uint256 addedAmount);
    event Unstaked(address indexed user, uint256 indexed tokenId, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _zkcToken, address _admin) public initializer {
        __ERC721_init("Vote Escrowed ZK Coin", "veZKC");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        zkcToken = ZKC(_zkcToken);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        
        // Initialize first point at index 0 with zero values
        // This ensures we always have a base point for calculations
        _globalPointHistory[0] = Point({
            bias: 0,
            slope: 0,
            updatedAt: block.timestamp
        });
    }

    // Staking functions (consolidated from StakingVault)
    function stake(uint256 amount, uint256 timestamp) external nonReentrant returns (uint256 tokenId) {
        if (amount == 0) revert ZeroAmount();
        
        // Enforce single active position per user
        if (userActivePosition[msg.sender] != 0) revert UserAlreadyHasActivePosition();
        
        timestamp = _timestampFloorToWeek(timestamp);
        if (timestamp <= block.timestamp + MIN_LOCK_WEEKS * WEEK) revert LockDurationTooShort();

        // Transfer ZKC from user
        IERC20(address(zkcToken)).safeTransferFrom(msg.sender, address(this), amount);

        // Mint veZKC NFT with voting/reward power
        tokenId = _stakeAndCheckpoint(msg.sender, amount, timestamp);

        // Track user's active position
        userActivePosition[msg.sender] = tokenId;

        emit Staked(msg.sender, amount, tokenId);
        return tokenId;
    }

    function _timestampFloorToWeek(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / WEEK) * WEEK;
    }

    function addToStake(uint256 tokenId, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(userActivePosition[msg.sender] == tokenId, "Not user's active position");

        address user = msg.sender;

        // Check that the lock hasn't expired
        LockInfo memory lock = locks[tokenId];
        require(block.timestamp < lock.lockEnd, "Lock has expired, please unstake first");

        // Transfer ZKC from user
        IERC20(address(zkcToken)).safeTransferFrom(user, address(this), amount);

        // Add to existing veZKC position (preserves existing decay)
        _addStakeAndCheckpoint(tokenId, amount);

        emit StakeAdded(user, tokenId, amount);
    }

    function extendLockToTime(uint256 tokenId, uint256 newLockEndTime) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(userActivePosition[msg.sender] == tokenId, "Not user's active position");
        
        // Cannot extend if delegated to someone else
        address delegatee = delegates(msg.sender);
        require(delegatee == msg.sender, "Cannot extend lock while delegated");

        // Check that the lock hasn't expired
        LockInfo memory lock = locks[tokenId];
        require(block.timestamp < lock.lockEnd, "Lock has expired, please unstake first");

        // Validate timestamp constraints (moved from _extendLockAndCheckpoint for consistency)
        uint256 roundedNewLockEndTime = _timestampFloorToWeek(newLockEndTime);
        require(roundedNewLockEndTime > lock.lockEnd, "Can only increase lock end time");
        require(roundedNewLockEndTime <= block.timestamp + MAXTIME, "Lock cannot exceed max time");

        // Extend the lock to new end time
        _extendLockAndCheckpoint(tokenId, newLockEndTime);

        emit LockExtended(tokenId, locks[tokenId].lockEnd);
    }

    function unstake(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(userActivePosition[msg.sender] == tokenId, "Not user's active position");

        address user = msg.sender;

        // Check that the lock has expired
        LockInfo memory lock = locks[tokenId];
        require(block.timestamp >= lock.lockEnd, "Lock has not expired yet");

        // Remove user's active position tracking
        delete userActivePosition[user];

        // Burn the veZKC NFT
        _burnLock(tokenId);

        // Transfer ZKC back to user
        IERC20(address(zkcToken)).safeTransfer(user, lock.amount);

        emit Unstaked(user, tokenId, lock.amount);
    }

    function burnExpiredNFT(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "NFT does not exist or already burned");

        LockInfo memory lock = locks[tokenId];
        require(block.timestamp >= lock.lockEnd, "Lock has not expired yet");

        address owner = ownerOf(tokenId);

        // Remove user's active position tracking if this was their active position
        if (userActivePosition[owner] == tokenId) {
            delete userActivePosition[owner];
        }

        // Anyone can burn expired NFTs to keep the system clean
        _burnLock(tokenId);
    }

    function _stakeAndCheckpoint(address to, uint256 amount, uint256 timestamp) internal returns (uint256) {
        uint256 tokenId = ++_currentTokenId;
        _mint(to, tokenId);

        LockInfo memory oldLock; // Empty lock (new mint)
        LockInfo memory newLock = LockInfo({amount: amount, lockEnd: timestamp});
        
        locks[tokenId] = newLock;
        
        // Get delegatee (self-delegate if not set)
        address delegatee = _delegatee[to];
        if (delegatee == address(0)) {
            delegatee = to;
            _delegatee[to] = to;
        }
        
        // Create checkpoint for voting power change
        _checkpoint(to, oldLock, newLock);

        return tokenId;
    }

    function _addStakeAndCheckpoint(uint256 tokenId, uint256 newAmount) internal {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        // Capture old state before modification
        LockInfo memory oldLock = locks[tokenId];
        require(block.timestamp < oldLock.lockEnd, "Lock has expired");

        // Create new lock state with added amount
        LockInfo memory newLock = LockInfo({
            amount: oldLock.amount + newAmount,
            lockEnd: oldLock.lockEnd
        });

        locks[tokenId] = newLock;
        
        address owner = ownerOf(tokenId);
        
        // Get delegatee (self-delegate if not set)
        address delegatee = _delegatee[owner];
        if (delegatee == address(0)) {
            delegatee = owner;
            _delegatee[owner] = owner;
        }
        
        // Create checkpoint for voting power change
        // This updates the delegatee's checkpoint (which could be owner or someone else)
        _checkpoint(owner, oldLock, newLock);

        emit LockIncreased(tokenId, newAmount, newLock.amount);
    }

    function _extendLockAndCheckpoint(uint256 tokenId, uint256 newLockEndTime) internal {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        // Capture old state before modification
        LockInfo memory oldLock = locks[tokenId];
        require(block.timestamp < oldLock.lockEnd, "Lock has expired");

        // Round down to nearest week boundary
        uint256 roundedNewLockEnd = _timestampFloorToWeek(newLockEndTime);

        require(roundedNewLockEnd > oldLock.lockEnd, "Can only increase lock end time");
        require(roundedNewLockEnd <= block.timestamp + MAXTIME, "Lock cannot exceed max time");

        // Create new lock state with extended end time
        LockInfo memory newLock = LockInfo({
            amount: oldLock.amount,
            lockEnd: roundedNewLockEnd
        });

        locks[tokenId] = newLock;
        
        address owner = ownerOf(tokenId);
        
        // Get delegatee (self-delegate if not set)
        address delegatee = _delegatee[owner];
        if (delegatee == address(0)) {
            delegatee = owner;
            _delegatee[owner] = owner;
        }
        
        // Create checkpoint for voting power change
        _checkpoint(owner, oldLock, newLock);
        
        // Note: No need to update delegation here since extensions are blocked while delegated

        emit LockExtended(tokenId, newLock.lockEnd);
    }

    function _burnLock(uint256 tokenId) internal {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        address owner = ownerOf(tokenId);
        
        // Capture old state before modification
        LockInfo memory oldLock = locks[tokenId];
        // Empty lock (burned)
        LockInfo memory newLock;
        
        delete locks[tokenId];
        _burn(tokenId);
        
        // Get delegatee (self-delegate if not set)
        address delegatee = _delegatee[owner];
        if (delegatee == address(0)) {
            delegatee = owner;
            _delegatee[owner] = owner;
        }
        
        // Create checkpoint for voting power change
        _checkpoint(owner, oldLock, newLock);

        emit LockExpired(tokenId);
    }

    function votingPower(uint256 tokenId) external view returns (uint256) {
        return _getVotingPower(tokenId);
    }

    function _getVotingPower(uint256 tokenId) internal view returns (uint256) {
        if (_ownerOf(tokenId) == address(0)) return 0;

        LockInfo memory lock = locks[tokenId];

        if (block.timestamp >= lock.lockEnd) return 0;

        /**
         * @dev Standard veToken formula: voting_power = (amount * remaining_time) / MAXTIME
         * @dev This gives natural incentives without artificial multipliers
         */
        uint256 remainingTime = lock.lockEnd - block.timestamp;
        return (lock.amount * remainingTime) / MAXTIME;
    }

    function _getRewardPower(uint256 tokenId) internal view returns (uint256) {
        if (_ownerOf(tokenId) == address(0)) return 0;

        LockInfo memory lock = locks[tokenId];

        if (block.timestamp >= lock.lockEnd) return 0;

        /// @dev Same formula as voting power for consistency
        uint256 remainingTime = lock.lockEnd - block.timestamp;
        return (lock.amount * remainingTime) / MAXTIME;
    }

    function _isValidLockWeeks(uint256 lockWeeks) internal pure returns (bool) {
        return lockWeeks >= MIN_LOCK_WEEKS && lockWeeks <= MAX_LOCK_WEEKS;
    }

    /**
     * @dev Week-based validation and conversion functions
     */
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

    /**
     * @dev IVotes implementation
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp); 
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function getVotes(address account) public view override returns (uint256) {
        /**
         * @dev Returns the voting power that 'account' can use (i.e., delegated TO them)
         * @dev Not the voting power they own but may have delegated away
         */
        uint256 epoch = _userPointEpoch[account];
        if (epoch == 0) return 0;
        
        Point memory lastPoint = _userPointHistory[account][epoch];
        
        /**
         * @dev Calculate current voting power from bias and slope
         * @dev voting_power(t) = bias + slope * (t - ts), where slope is negative
         */
        int128 dt = int128(int256(block.timestamp - lastPoint.updatedAt));
        int128 bias = lastPoint.bias + lastPoint.slope * dt;
        
        /// @dev Ensure non-negative (voting power cannot be negative)
        if (bias < 0) bias = 0;
        
        return uint256(uint128(bias));
    }

    function getPastVotes(address account, uint256 timepoint) public view override returns (uint256) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        
        // Returns the voting power that 'account' could use at the given timepoint
        // Binary search for the right epoch at the given timestamp
        uint256 epoch = _findUserTimestampEpoch(account, timepoint);
        if (epoch == 0) return 0;
        
        Point memory uPoint = _userPointHistory[account][epoch];
        
        /// @dev Calculate voting power at that timestamp (no estimation needed!)
        int128 dt = int128(int256(timepoint - uPoint.updatedAt));
        int128 bias = uPoint.bias + uPoint.slope * dt;
        
        /// @dev Ensure non-negative
        if (bias < 0) bias = 0;
        
        return uint256(uint128(bias));
    }

    function getTotalVotes() public view returns (uint256) {
        if (_globalPointEpoch == 0) return 0;
        
        Point memory lastPoint = _globalPointHistory[_globalPointEpoch];
        
        /// @dev Calculate current total voting power from bias and slope
        int128 dt = int128(int256(block.timestamp - lastPoint.updatedAt));
        int128 bias = lastPoint.bias + lastPoint.slope * dt;
        
        /// @dev Apply scheduled slope changes that have occurred
        uint256 t = (lastPoint.updatedAt / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; i++) {
            t += WEEK;
            if (t > block.timestamp) break;
            
            int128 dSlope = slopeChanges[t];
            if (dSlope != 0) {
                /// @dev Slope change makes the slope less negative (decay slows)
                lastPoint.slope += dSlope;
                /// @dev Adjust bias for the time period with old slope
                int128 dt2 = int128(int256(t - lastPoint.updatedAt));
                bias = bias + lastPoint.slope * dt2;
                lastPoint.updatedAt = t;
            }
        }
        
        /// @dev Final adjustment from last slope change to current time
        if (block.timestamp > lastPoint.updatedAt) {
            dt = int128(int256(block.timestamp - lastPoint.updatedAt));
            bias = bias + lastPoint.slope * dt;
        }
        
        /// @dev Ensure non-negative
        if (bias < 0) bias = 0;
        
        return uint256(uint128(bias));
    }

    function getPastTotalSupply(uint256 timepoint) public view override returns (uint256) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        
        /// @dev Binary search for the right epoch at the given timestamp
        uint256 epoch = _findTimestampEpoch(timepoint);
        if (epoch == 0) return 0;
        
        Point memory point = _globalPointHistory[epoch];
        
        /// @dev Calculate total supply at that timestamp (no estimation needed!)
        int128 dt = int128(int256(timepoint - point.updatedAt));
        int128 bias = point.bias + point.slope * dt;
        
        /// @dev Apply slope changes between point.ts and timepoint
        uint256 t = (point.updatedAt / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; i++) {
            t += WEEK;
            if (t > timepoint) break;
            
            int128 dSlope = slopeChanges[t];
            if (dSlope != 0) {
                point.slope += dSlope;
                int128 dt2 = int128(int256(t - point.updatedAt));
                bias = bias + point.slope * dt2;
                point.updatedAt = t;
            }
        }
        
        /// @dev Final adjustment
        if (timepoint > point.updatedAt) {
            dt = int128(int256(timepoint - point.updatedAt));
            bias = bias + point.slope * dt;
        }
        
        /// @dev Ensure non-negative
        if (bias < 0) bias = 0;
        
        return uint256(uint128(bias));
    }

    function delegates(address account) public view override returns (address) {
        address delegatee = _delegatee[account];
        return delegatee == address(0) ? account : delegatee;
    }

    function delegate(address delegatee) public override {
        address account = _msgSender();
        
        /// @dev Get both user's active positions
        uint256 myTokenId = userActivePosition[account];
        uint256 delegateeTokenId = userActivePosition[delegatee];
        
        require(myTokenId != 0, "No active position");
        require(delegateeTokenId != 0, "Delegatee has no active position");
        
        LockInfo memory myLock = locks[myTokenId];
        LockInfo memory delegateeLock = locks[delegateeTokenId];
        
        /// @dev Extend my lock to match delegatee's lock if needed
        if (delegateeLock.lockEnd > myLock.lockEnd) {
            _extendLockAndCheckpoint(myTokenId, delegateeLock.lockEnd);
        }
        
        _delegate(account, delegatee);
    }

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        override
    {
        revert("Not implemented");
    }

    function _delegate(address account, address delegatee) internal {
        address oldDelegate = delegates(account);
        _delegatee[account] = delegatee;

        /// @dev Checkpoint delegation change
        _checkpointDelegation(account, oldDelegate, delegatee);

        emit DelegateChanged(account, oldDelegate, delegatee);
        emit DelegateVotesChanged(
            delegatee,
            getVotes(oldDelegate),
            getVotes(delegatee)
        );
    }

    /**
     * @dev Current voting power (not checkpointed, calculated live)
     */
    function getCurrentVotingPower(address account) external view returns (uint256) {
        return _getAccountRewardPower(account);
    }

    /**
     * @dev IRewardPower implementation
     */
    function getRewardPower(address account) external view override returns (uint256) {
        return _getAccountRewardPower(account);
    }

    // TODO
    function getPastRewardPower(address account, uint256 timepoint) external view override returns (uint256) {
        return _getAccountRewardPower(account);
    }

    // TODO
    function getTotalRewardPower() external view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 1; i <= _currentTokenId; i++) {
            if (_ownerOf(i) != address(0)) {
                total += _getRewardPower(i);
            }
        }
        return total;
    }

    // TODO
    function getPastTotalRewardPower(uint256 timepoint) external view override returns (uint256) {
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
        return interfaceId == type(IERC721).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Public functions to get lock information
     */
    function getMaxVotingPower(uint256 amount) external pure returns (uint256) {
        /// @dev Maximum voting power when locked for MAXTIME
        return amount;
    }

    function getVotingPowerForWeeks(uint256 amount, uint256 lockWeeks) external pure returns (uint256) {
        /// @dev Calculate initial voting power for a given amount and lock weeks
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
    
    // Custom errors for staking functions
    error ZeroAmount();
    error LockDurationTooShort();
    error UserAlreadyHasActivePosition();

    /**
     * @dev Helper Functions for Points System
     */
    
    /**
     * @dev Binary search to find user's point at a specific timestamp
     */
    function _findUserTimestampEpoch(address user, uint256 timestamp) internal view returns (uint256) {
        uint256 min = 0;
        uint256 max = _userPointEpoch[user];
        
        /// @dev Binary search by timestamp
        while (min < max) {
            uint256 mid = (min + max + 1) / 2;
            if (_userPointHistory[user][mid].updatedAt <= timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        
        return min;
    }
    
    /**
     * @dev Binary search to find global point at a specific timestamp
     */
    function _findTimestampEpoch(uint256 timestamp) internal view returns (uint256) {
        uint256 min = 0;
        uint256 max = _globalPointEpoch;
        
        /// @dev Binary search by timestamp
        while (min < max) {
            uint256 mid = (min + max + 1) / 2;
            if (_globalPointHistory[mid].updatedAt <= timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        
        return min;
    }
    
    /**
     * @dev Main checkpoint function that updates user and global points
     * @dev Following standard veToken pattern with explicit old/new lock states
     */
    function _checkpoint(
        address account, 
        LockInfo memory oldLock, 
        LockInfo memory newLock
    ) internal {
        // Track the users old point (if one exists, i.e. we are topping up or extending a lock)
        Point memory userOldPoint;
        // Track the users new point (either updated from old point, or newly created)
        Point memory userNewPoint;
        
        // Track the impact on the global point's slope value as a result of the user's lock changes.
        int128 globalOldSlopeDelta = 0;
        int128 globalNewSlopeDelta = 0;
        
        // Get the delegatee (self-delegate if not set)
        address user = delegates(account);
        
        // Calculate old point from explicit oldLock state, if it hasn't expired.
        if (oldLock.lockEnd > block.timestamp && oldLock.amount > 0) {
            // Calculate old voting power and slope from oldLock
            uint256 oldRemainingTime = oldLock.lockEnd - block.timestamp;
            uint256 oldPower = (oldLock.amount * oldRemainingTime) / MAXTIME;
            int128 oldSlope = -int128(int256(oldLock.amount)) / iMAXTIME;
            
            userOldPoint = Point({
                bias: int128(int256(oldPower)),
                slope: oldSlope,
                updatedAt: block.timestamp
            });
        }
        
        // Calculate new point from explicit newLock state
        if (newLock.lockEnd > block.timestamp && newLock.amount > 0) {
            // Calculate new voting power and slope from newLock
            uint256 newRemainingTime = newLock.lockEnd - block.timestamp;
            uint256 newPower = (newLock.amount * newRemainingTime) / MAXTIME;
            int128 newSlope = -int128(int256(newLock.amount)) / iMAXTIME;
            
            userNewPoint = Point({
                bias: int128(int256(newPower)),
                slope: newSlope,
                updatedAt: block.timestamp
            });
        }

        // Read slope changes that are already scheduled at these timestamps.
        // oldLock.lockEnd can be in the past or in the future
        // newLock.lockEnd can either be in the future, or 0 (used for unstaking after expiry)
        globalOldSlopeDelta = slopeChanges[oldLock.lockEnd];
        if (newLock.lockEnd != 0) {
            if (newLock.lockEnd == oldLock.lockEnd) {
                globalNewSlopeDelta = globalOldSlopeDelta;
            } else {
                globalNewSlopeDelta = slopeChanges[newLock.lockEnd];
            }
        }
        
        // Update user point history
        uint256 userEpoch = _userPointEpoch[user] + 1;
        _userPointEpoch[user] = userEpoch;
        _userPointHistory[user][userEpoch] = userNewPoint;
        
        // Update global point
        Point memory lastGlobalPoint = Point({bias: 0, slope: 0, updatedAt: block.timestamp});
        uint256 globalEpoch = _globalPointEpoch;
        if (globalEpoch > 0) {
            lastGlobalPoint = _globalPointHistory[globalEpoch];
        }

        uint256 lastCheckpoint = lastGlobalPoint.updatedAt;
        
        // Backfill weekly global points.
        // This ensures getPastTotalSupply works correctly for any timestamp 
        // (since timestamps are always rounded down to the week on lock creation/extension)
        {
            uint256 currentTimestamp = _timestampFloorToWeek(lastCheckpoint); // Round down to week
            for (uint256 i = 0; i < 255; i++) {
                currentTimestamp += WEEK;
                int128 currentScheduledSlopeChange = 0;
                
                if (currentTimestamp > block.timestamp) {
                    currentTimestamp = block.timestamp; // Don't go beyond current time
                } else {
                    currentScheduledSlopeChange = slopeChanges[currentTimestamp]; // Get slope change for this week
                }
                
                int128 biasDelta = lastGlobalPoint.slope * int128(int256(currentTimestamp - lastCheckpoint));
                lastGlobalPoint.bias -= biasDelta;
                // If decayed to zero mid week, bias could be negative in following week.
                // Ensure bias never goes negative (a user can't have negative power).
                if (lastGlobalPoint.bias < 0) {
                    lastGlobalPoint.bias = 0;
                }
                
                lastGlobalPoint.slope += currentScheduledSlopeChange;
                // Slope can never go negative. Added as a sanity check.
                if (lastGlobalPoint.slope < 0) {
                    lastGlobalPoint.slope = 0;
                }

                lastCheckpoint = currentTimestamp;
                lastGlobalPoint.updatedAt = currentTimestamp;
                globalEpoch += 1;
                
                        // Unlikely, but if the current timestamp (which is rounded down to the week)
        // is the same as the block timestamp, we don't store it in history yet as
        // we still need to apply the users changes to it.
        if (lastGlobalPoint.updatedAt == block.timestamp) {
            break;
        } else {
            _globalPointHistory[globalEpoch] = lastGlobalPoint;
        }                
            }
        }

        // At this point we have backfilled the global point history for all weeks before the current block timestamp.
        // Now apply the user's changes, and store the new latest global point.
        Point memory newGlobalPoint = Point({
            bias: lastGlobalPoint.bias + userNewPoint.bias - userOldPoint.bias,
            slope: lastGlobalPoint.slope + userNewPoint.slope - userOldPoint.slope,
            updatedAt: block.timestamp
        });
        
        // Ensure non-negative bias and slope
        if (newGlobalPoint.bias < 0) {
            newGlobalPoint.bias = 0;
        }

        if (newGlobalPoint.slope < 0) {
            newGlobalPoint.slope = 0;
        }

        // If we haven't already created a global point at the current block timestamp,
        // we increment the global point epoch so we can store it new.
        // 
        // If we already created a global point at this block timestamp due to a previous
        // transaction within the same block, we don't need to increment the global point epoch. 
        // We instead just update the existing global point.
        if (lastGlobalPoint.updatedAt != block.timestamp) {
            globalEpoch += 1;
        }
        
        // Update global point history with final point
        _globalPointHistory[globalEpoch] = newGlobalPoint;
        _globalPointEpoch = globalEpoch;
        
        // Schedule slope changes.
        if (oldLock.lockEnd > block.timestamp) {
            // Cancel out the slope change that was previously scheduled by the old point.
            // When a lock is removed or expires, slope becomes less negative (decay slows), 
            // so we add to cancel out the decay.
            globalOldSlopeDelta += userOldPoint.slope;
            // If it is a new deposit, not extension, we apply the new slope to the same point.
            if (newLock.lockEnd == oldLock.lockEnd) {
                globalOldSlopeDelta -= userNewPoint.slope;
            }
            slopeChanges[oldLock.lockEnd] = globalOldSlopeDelta;
        }

        if (newLock.lockEnd > block.timestamp) {
            // If its an extension, we schedule the slope to disappear at the new point.
            if (newLock.lockEnd > oldLock.lockEnd) {
                globalNewSlopeDelta -= userNewPoint.slope;
                slopeChanges[newLock.lockEnd] = globalNewSlopeDelta;
            }
        }
    }
    
    /**
     * @dev Handle delegation checkpointing for single NFT per user
     */
    function _checkpointDelegation(address account, address oldDelegatee, address newDelegatee) internal {
        // Get the user's single active position
        uint256 tokenId = userActivePosition[account];
        if (tokenId == 0) return; // No active position to delegate
        
        LockInfo memory lock = locks[tokenId];
        if (lock.lockEnd <= block.timestamp) return; // Expired lock has no power
        
        // When called from _addStakeAndCheckpoint with same old and new delegatee,
        // this is a re-checkpoint to update the delegatee with new amount
        if (oldDelegatee == newDelegatee && oldDelegatee != address(0)) {
            // This is a special case: updating delegation amount after top-up
            // We need to calculate the difference and add it to delegatee
            // The main _checkpoint already handled updating the owner's checkpoint
            // So we just need to update the delegatee's checkpoint with the difference
           
            // TODO: skip since _checkpoint already handles it correctly?
            return;
        }
        
        // Normal delegation change: transfer power from old to new delegatee
        // Create lock states for checkpointing
        LockInfo memory emptyLock; // Empty lock for removal/addition
        
        // Remove from old delegatee's checkpoint
        if (oldDelegatee != address(0) && oldDelegatee != newDelegatee) {
            _checkpoint(oldDelegatee, lock, emptyLock);
        }
        
        // Add to new delegatee's checkpoint
        if (newDelegatee != address(0) && oldDelegatee != newDelegatee) {
            _checkpoint(newDelegatee, emptyLock, lock);
        }
    }
}
