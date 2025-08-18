// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {veZKC} from "../../src/veZKC.sol";
import {ZKC} from "../../src/ZKC.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract veZKCHandler is Test {
    veZKC public veToken;
    ZKC public zkc;
    
    // Test actors
    address[] public actors;
    address public currentActor;
    
    // Configuration
    uint256 constant MIN_ACTORS = 50;
    uint256 constant MAX_ACTORS = 100;
    uint256 constant MIN_STAKE_AMOUNT = 1e18; // 1 ZKC
    uint256 constant MAX_STAKE_AMOUNT = 10_000e18; // 10k ZKC
    uint256 constant MIN_TIME_WARP = 1 days;
    uint256 constant MAX_TIME_WARP = 4 weeks;
    
    // Ghost variables for tracking state
    uint256 public ghost_totalStaked;
    uint256 public ghost_totalUnstaked;
    mapping(address => uint256) public ghost_userStaked;
    mapping(address => uint256) public ghost_userTokenId;
    mapping(address => bool) public ghost_hasActivePosition;
    mapping(uint256 => uint256) public ghost_tokenAmount;
    mapping(uint256 => uint256) public ghost_tokenExpiry;
    
    // Track historical values for consistency checks
    uint256[] public ghost_historicalTimestamps;
    mapping(uint256 => uint256) public ghost_historicalTotalSupply;
    
    // Action counters for debugging
    uint256 public callCount;
    uint256 public stakeCount;
    uint256 public addStakeCount;
    uint256 public extendCount;
    uint256 public unstakeCount;
    uint256 public timeWarpCount;
    
    modifier useActor() {
        // Select random actor
        currentActor = actors[bound(uint256(keccak256(abi.encode(callCount))), 0, actors.length - 1)];
        vm.startPrank(currentActor);
        callCount++;
        _;
        vm.stopPrank();
    }
    
    constructor(veZKC _veToken, ZKC _zkc) {
        veToken = _veToken;
        zkc = _zkc;
        
        // Create test actors
        uint256 numActors = bound(uint256(keccak256("actors")), MIN_ACTORS, MAX_ACTORS);
        for (uint256 i = 0; i < numActors; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            
            // Fund actor with ZKC
            deal(address(zkc), actor, MAX_STAKE_AMOUNT * 100);
            
            // Pre-approve veToken to spend ZKC
            vm.prank(actor);
            zkc.approve(address(veToken), type(uint256).max);
        }
    }
    
    // Action: Stake tokens
    function stake(uint256 seed) public useActor {
        // Skip if user already has active position
        if (ghost_hasActivePosition[currentActor]) {
            return;
        }
        
        // Check if user has sufficient balance, refill if needed
        uint256 balance = zkc.balanceOf(currentActor);
        if (balance < MIN_STAKE_AMOUNT) {
            deal(address(zkc), currentActor, MAX_STAKE_AMOUNT * 10);
            balance = MAX_STAKE_AMOUNT * 10;
        }
        uint256 maxAmount = balance > MAX_STAKE_AMOUNT ? MAX_STAKE_AMOUNT : balance;
        uint256 amount = bound(seed, MIN_STAKE_AMOUNT, maxAmount);
        
        // Generate random parameters with longer minimum lock times
        uint256 lockWeeks = bound(seed >> 8, 20, Constants.MAX_STAKE_WEEKS); // Min 20 weeks instead of 4
        uint256 expires = block.timestamp + (lockWeeks * 1 weeks);
        
        console.log(string.concat("STAKE_PARAMS: amount=", Strings.toString(amount), " lockWeeks=", Strings.toString(lockWeeks)));
        
        // Execute stake
        try veToken.stake(amount, expires) returns (uint256 tokenId) {
            // Update ghost variables
            ghost_totalStaked += amount;
            ghost_userStaked[currentActor] += amount;
            ghost_userTokenId[currentActor] = tokenId;
            ghost_hasActivePosition[currentActor] = true;
            ghost_tokenAmount[tokenId] = amount;
            (,uint256 lockEnd) = veToken.getStakedAmountAndExpiry(currentActor);
            ghost_tokenExpiry[tokenId] = lockEnd;
            
            stakeCount++;
            
            console.log(string.concat("STAKE SUCCESS: amount=", Strings.toString(amount), " tokenId=", Strings.toString(tokenId), " lockEnd=", Strings.toString(lockEnd)));
            
            // Record historical snapshot
            _recordHistoricalSnapshot();
        } catch {
            console.log(string.concat("STAKE FAILED: amount=", Strings.toString(amount), " expires=", Strings.toString(expires)));
        }
    }
    
    // Action: Add to existing stake
    function addToStake(uint256 seed) public useActor {
        // If user doesn't have active position, create one instead
        if (!ghost_hasActivePosition[currentActor]) {
            console.log("AUTO-STAKING: User has no position, creating stake first");
            stake(seed);
        }
        
        uint256 tokenId = ghost_userTokenId[currentActor];
        
        // Check if position is expired
        if (block.timestamp >= ghost_tokenExpiry[tokenId]) {
            console.log("AUTO-EXTENDING: Position is expired, extending");
            extendStake(seed);
        }
        
        // Check if user has sufficient balance, refill if needed
        uint256 balance = zkc.balanceOf(currentActor);
        if (balance < MIN_STAKE_AMOUNT) {
            deal(address(zkc), currentActor, MAX_STAKE_AMOUNT * 10);
            balance = MAX_STAKE_AMOUNT * 10;
        }
        uint256 maxAmount = balance > MAX_STAKE_AMOUNT ? MAX_STAKE_AMOUNT : balance;
        uint256 amount = bound(seed, MIN_STAKE_AMOUNT, maxAmount);
        
        console.log(string.concat("ADD_PARAMS: amount=", Strings.toString(amount), " toTokenId=", Strings.toString(tokenId)));
        
        // Execute add to stake
        try veToken.addToStake(amount) {
            // Update ghost variables
            ghost_totalStaked += amount;
            ghost_userStaked[currentActor] += amount;
            ghost_tokenAmount[tokenId] += amount;
            
            addStakeCount++;
            
            console.log(string.concat("ADD_TO_STAKE SUCCESS: amount=", Strings.toString(amount), " tokenId=", Strings.toString(tokenId)));
            
            // Record historical snapshot
            _recordHistoricalSnapshot();
        } catch {
            console.log(string.concat("ADD_TO_STAKE FAILED: amount=", Strings.toString(amount), " tokenId=", Strings.toString(tokenId)));
        }
    }
    
    // Action: Extend lock duration
    function extendStake(uint256 seed) public useActor {
        // If user doesn't have active position, create one instead
        if (!ghost_hasActivePosition[currentActor]) {
            console.log("AUTO-STAKING: User has no position, creating stake first");
            stake(seed);
        }
        
        uint256 tokenId = ghost_userTokenId[currentActor];
        uint256 currentExpiry = ghost_tokenExpiry[tokenId];
        
        // Generate new expiry (extend by 1-52 weeks)
        uint256 additionalWeeks = bound(seed, 8, 52);
        uint256 newExpiry = currentExpiry + (additionalWeeks * 1 weeks);
        
        console.log(string.concat("EXTEND_PARAMS: tokenId=", Strings.toString(tokenId), " addWeeks=", Strings.toString(additionalWeeks)));
        
        // Ensure doesn't exceed max duration from current time
        uint256 maxExpiry = block.timestamp + Constants.MAX_STAKE_TIME_S;
        if (newExpiry > maxExpiry) {
            newExpiry = maxExpiry;
        }
        
        // Execute extend
        try veToken.extendStakeLockup(newExpiry) {
            // Update ghost variables
            (,uint256 lockEnd) = veToken.getStakedAmountAndExpiry(currentActor);
            ghost_tokenExpiry[tokenId] = lockEnd;
            
            extendCount++;
            
            console.log(string.concat("EXTEND_STAKE SUCCESS: tokenId=", Strings.toString(tokenId), " newExpiry=", Strings.toString(newExpiry), " actualLockEnd=", Strings.toString(lockEnd)));
            
            // Record historical snapshot
            _recordHistoricalSnapshot();
        } catch {
            console.log(string.concat("EXTEND_STAKE FAILED: tokenId=", Strings.toString(tokenId), " newExpiry=", Strings.toString(newExpiry)));
        }
    }
    
    // Action: Unstake tokens
    function unstake() public useActor {
        if (!ghost_hasActivePosition[currentActor]) {
            return;
        }
        
        uint256 tokenId = ghost_userTokenId[currentActor];
        
        // Check if lock has expired
        if (block.timestamp < ghost_tokenExpiry[tokenId]) {
            return;
        }
        
        uint256 amountToUnstake = ghost_tokenAmount[tokenId];
        
        // Execute unstake
        try veToken.unstake() {
            // Update ghost variables
            ghost_totalUnstaked += amountToUnstake;
            ghost_userStaked[currentActor] -= amountToUnstake;
            ghost_hasActivePosition[currentActor] = false;
            delete ghost_userTokenId[currentActor];
            delete ghost_tokenAmount[tokenId];
            delete ghost_tokenExpiry[tokenId];
            
            unstakeCount++;
            
            console.log(string.concat("UNSTAKE SUCCESS: amount=", Strings.toString(amountToUnstake), " tokenId=", Strings.toString(tokenId)));
            
            // Record historical snapshot
            _recordHistoricalSnapshot();
        } catch {
            console.log(string.concat("UNSTAKE FAILED: tokenId=", Strings.toString(tokenId), " expiry=", Strings.toString(ghost_tokenExpiry[tokenId]), " currentTime=", Strings.toString(block.timestamp)));
        }
    }
    
    // Action: Advance time
    function warpTime(uint256 seed) public {
        uint256 timeToWarp = bound(seed, MIN_TIME_WARP, MAX_TIME_WARP);
        uint256 oldTime = block.timestamp;
        uint256 warpHours = timeToWarp / 1 hours;
        console.log(string.concat("WARP_PARAMS: hours=", Strings.toString(warpHours)));
        
        skip(timeToWarp);
        timeWarpCount++;
        
        console.log(string.concat("WARP_TIME: from=", Strings.toString(oldTime), " to=", Strings.toString(block.timestamp), " delta=", Strings.toString(timeToWarp)));
        
        // Record historical snapshot after time warp
        _recordHistoricalSnapshot();
    }
    
    // Helper: Record historical snapshot for later verification
    function _recordHistoricalSnapshot() internal {
        uint256 timestamp = block.timestamp;
        
        // Only record if this is a new timestamp and it's not block 0
        if (timestamp > 0 && 
            (ghost_historicalTimestamps.length == 0 || 
             ghost_historicalTimestamps[ghost_historicalTimestamps.length - 1] < timestamp)) {
            
            ghost_historicalTimestamps.push(timestamp);
            
            // Record the total supply at this timestamp for later comparison
            // Use timestamp - 1 to ensure we're definitely in the past when we check later
            if (timestamp > 1) {
                uint256 historicalSupply = veToken.getPastTotalSupply(timestamp - 1);
                ghost_historicalTotalSupply[timestamp] = historicalSupply;
            }
        }
    }
    
    // Weighted action selector for more realistic testing
    function performAction(uint256 seed) public {
        uint256 action = seed % 100;
        
        console.log(string.concat(
            "=== ACTION: seed=", Strings.toString(action),
            " actor=", Strings.toHexString(currentActor),
            " time=", Strings.toString(block.timestamp)
        ));
        
        if (action < 20) {
            // 20% chance: stake (prioritize getting users started)
            console.log("Action: STAKE");
            stake(seed >> 8);
        } else if (action < 50) {
            // 30% chance: add to stake (will auto-stake if needed)
            console.log("Action: ADD_TO_STAKE");
            addToStake(seed >> 8);
        } else if (action < 80) {
            // 30% chance: extend (will auto-stake if needed)
            console.log("Action: EXTEND_STAKE");
            extendStake(seed >> 8);
        } else if (action < 90) {
            // 10% chance: unstake
            console.log("Action: UNSTAKE");
            unstake();
        } else {
            // 10% chance: warp time
            console.log("Action: WARP_TIME");
            warpTime(seed >> 8);
        }
    }
    
    // View functions for invariant assertions
    function getTotalActiveStaked() public view returns (uint256) {
        return ghost_totalStaked - ghost_totalUnstaked;
    }
    
    function sumAllUserStaked() public view returns (uint256 sum) {
        for (uint256 i = 0; i < actors.length; i++) {
            sum += ghost_userStaked[actors[i]];
        }
    }
    
    function getActorCount() public view returns (uint256) {
        return actors.length;
    }
    
    function getHistoricalSnapshotCount() public view returns (uint256) {
        return ghost_historicalTimestamps.length;
    }
}