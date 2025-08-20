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
    mapping(address => bool) public ghost_isWithdrawing;
    mapping(address => uint256) public ghost_withdrawalRequestTime;
    mapping(uint256 => uint256) public ghost_tokenAmount;

    // Track historical values for consistency checks
    uint256[] public ghost_historicalTimestamps;
    mapping(uint256 => uint256) public ghost_historicalTotalSupply;

    // Action counters for debugging
    uint256 public callCount;
    uint256 public stakeCount;
    uint256 public addStakeCount;
    uint256 public initiateWithdrawalCount;
    uint256 public completeWithdrawalCount;
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

        console.log(string.concat("STAKE_PARAMS: amount=", Strings.toString(amount)));

        // Execute stake
        try veToken.stake(amount) returns (uint256 tokenId) {
            // Update ghost variables
            ghost_totalStaked += amount;
            ghost_userStaked[currentActor] += amount;
            ghost_userTokenId[currentActor] = tokenId;
            ghost_hasActivePosition[currentActor] = true;
            ghost_isWithdrawing[currentActor] = false;
            ghost_tokenAmount[tokenId] = amount;

            stakeCount++;

            console.log(
                string.concat(
                    "STAKE SUCCESS: amount=", Strings.toString(amount), " tokenId=", Strings.toString(tokenId)
                )
            );

            // Record historical snapshot
            _recordHistoricalSnapshot();
        } catch {
            console.log(string.concat("STAKE FAILED: amount=", Strings.toString(amount)));
        }
    }

    // Action: Add to existing stake
    function addToStake(uint256 seed) public useActor {
        // If user doesn't have active position, create one instead
        if (!ghost_hasActivePosition[currentActor]) {
            console.log("AUTO-STAKING: User has no position, creating stake first");
            stake(seed);
            return;
        }

        // Cannot add to stake while withdrawing
        if (ghost_isWithdrawing[currentActor]) {
            console.log("SKIP: Cannot add to stake while withdrawing");
            return;
        }

        uint256 tokenId = ghost_userTokenId[currentActor];

        // Check if user has sufficient balance, refill if needed
        uint256 balance = zkc.balanceOf(currentActor);
        if (balance < MIN_STAKE_AMOUNT) {
            deal(address(zkc), currentActor, MAX_STAKE_AMOUNT * 10);
            balance = MAX_STAKE_AMOUNT * 10;
        }
        uint256 maxAmount = balance > MAX_STAKE_AMOUNT ? MAX_STAKE_AMOUNT : balance;
        uint256 amount = bound(seed, MIN_STAKE_AMOUNT, maxAmount);

        console.log(
            string.concat("ADD_PARAMS: amount=", Strings.toString(amount), " toTokenId=", Strings.toString(tokenId))
        );

        // Execute add to stake
        try veToken.addToStake(amount) {
            // Update ghost variables
            ghost_totalStaked += amount;
            ghost_userStaked[currentActor] += amount;
            ghost_tokenAmount[tokenId] += amount;

            addStakeCount++;

            console.log(
                string.concat(
                    "ADD_TO_STAKE SUCCESS: amount=", Strings.toString(amount), " tokenId=", Strings.toString(tokenId)
                )
            );

            // Record historical snapshot
            _recordHistoricalSnapshot();
        } catch {
            console.log(
                string.concat(
                    "ADD_TO_STAKE FAILED: amount=", Strings.toString(amount), " tokenId=", Strings.toString(tokenId)
                )
            );
        }
    }

    // Action: Initiate withdrawal
    function initiateWithdrawal() public useActor {
        if (!ghost_hasActivePosition[currentActor]) {
            return;
        }

        // Skip if already withdrawing
        if (ghost_isWithdrawing[currentActor]) {
            return;
        }

        uint256 tokenId = ghost_userTokenId[currentActor];

        console.log(string.concat("INITIATE_WITHDRAWAL_PARAMS: tokenId=", Strings.toString(tokenId)));

        // Execute initiate withdrawal
        try veToken.initiateUnstake() {
            // Update ghost variables
            ghost_isWithdrawing[currentActor] = true;
            ghost_withdrawalRequestTime[currentActor] = vm.getBlockTimestamp();

            initiateWithdrawalCount++;

            console.log(
                string.concat(
                    "INITIATE_WITHDRAWAL SUCCESS: tokenId=",
                    Strings.toString(tokenId),
                    " requestTime=",
                    Strings.toString(vm.getBlockTimestamp())
                )
            );

            // Record historical snapshot
            _recordHistoricalSnapshot();
        } catch {
            console.log(string.concat("INITIATE_WITHDRAWAL FAILED: tokenId=", Strings.toString(tokenId)));
        }
    }

    // Action: Complete withdrawal
    function completeWithdrawal() public useActor {
        if (!ghost_hasActivePosition[currentActor] || !ghost_isWithdrawing[currentActor]) {
            return;
        }

        uint256 withdrawalRequestTime = ghost_withdrawalRequestTime[currentActor];

        // Check if withdrawal period has passed
        if (vm.getBlockTimestamp() < withdrawalRequestTime + Constants.WITHDRAWAL_PERIOD) {
            return;
        }

        uint256 tokenId = ghost_userTokenId[currentActor];
        uint256 amountToUnstake = ghost_tokenAmount[tokenId];

        console.log(
            string.concat(
                "COMPLETE_WITHDRAWAL_PARAMS: tokenId=",
                Strings.toString(tokenId),
                " amount=",
                Strings.toString(amountToUnstake)
            )
        );

        // Execute complete withdrawal
        try veToken.completeUnstake() {
            // Update ghost variables
            ghost_totalUnstaked += amountToUnstake;
            ghost_userStaked[currentActor] -= amountToUnstake;
            ghost_hasActivePosition[currentActor] = false;
            ghost_isWithdrawing[currentActor] = false;
            ghost_withdrawalRequestTime[currentActor] = 0;
            delete ghost_userTokenId[currentActor];
            delete ghost_tokenAmount[tokenId];

            completeWithdrawalCount++;

            console.log(
                string.concat(
                    "COMPLETE_WITHDRAWAL SUCCESS: amount=",
                    Strings.toString(amountToUnstake),
                    " tokenId=",
                    Strings.toString(tokenId)
                )
            );

            // Record historical snapshot
            _recordHistoricalSnapshot();
        } catch {
            console.log(
                string.concat(
                    "COMPLETE_WITHDRAWAL FAILED: tokenId=",
                    Strings.toString(tokenId),
                    " requestTime=",
                    Strings.toString(withdrawalRequestTime),
                    " currentTime=",
                    Strings.toString(vm.getBlockTimestamp())
                )
            );
        }
    }

    // Action: Advance time
    function warpTime(uint256 seed) public {
        uint256 timeToWarp = bound(seed, MIN_TIME_WARP, MAX_TIME_WARP);
        uint256 oldTime = vm.getBlockTimestamp();
        uint256 warpHours = timeToWarp / 1 hours;
        console.log(string.concat("WARP_PARAMS: hours=", Strings.toString(warpHours)));

        skip(timeToWarp);
        timeWarpCount++;

        console.log(
            string.concat(
                "WARP_TIME: from=",
                Strings.toString(oldTime),
                " to=",
                Strings.toString(vm.getBlockTimestamp()),
                " delta=",
                Strings.toString(timeToWarp)
            )
        );

        // Record historical snapshot after time warp
        _recordHistoricalSnapshot();
    }

    // Helper: Record historical snapshot for later verification
    function _recordHistoricalSnapshot() internal {
        uint256 timestamp = vm.getBlockTimestamp();

        // Only record if this is a new timestamp and it's not block 0
        if (
            timestamp > 0
                && (
                    ghost_historicalTimestamps.length == 0
                        || ghost_historicalTimestamps[ghost_historicalTimestamps.length - 1] < timestamp
                )
        ) {
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

        console.log(
            string.concat(
                "=== ACTION: seed=",
                Strings.toString(action),
                " actor=",
                Strings.toHexString(currentActor),
                " time=",
                Strings.toString(vm.getBlockTimestamp())
            )
        );

        if (action < 25) {
            // 25% chance: stake (prioritize getting users started)
            console.log("Action: STAKE");
            stake(seed >> 8);
        } else if (action < 50) {
            // 25% chance: add to stake (will auto-stake if needed)
            console.log("Action: ADD_TO_STAKE");
            addToStake(seed >> 8);
        } else if (action < 70) {
            // 20% chance: initiate withdrawal
            console.log("Action: INITIATE_WITHDRAWAL");
            initiateWithdrawal();
        } else if (action < 85) {
            // 15% chance: complete withdrawal
            console.log("Action: COMPLETE_WITHDRAWAL");
            completeWithdrawal();
        } else {
            // 15% chance: warp time
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

    function getActiveNonWithdrawingStaked() public view returns (uint256 sum) {
        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];
            if (ghost_hasActivePosition[actor] && !ghost_isWithdrawing[actor]) {
                sum += ghost_userStaked[actor];
            }
        }
    }
}
