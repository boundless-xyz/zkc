// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Checkpoints} from "../../src/libraries/Checkpoints.sol";
import {Constants} from "../../src/libraries/Constants.sol";

/**
 * @title Checkpoints Library Test
 * @notice Unit tests for the core checkpoint logic
 * @dev Tests the pure library functions using mock storage structures
 */
contract CheckpointsTest is Test {
    using Checkpoints for Checkpoints.UserCheckpointStorage;
    using Checkpoints for Checkpoints.GlobalCheckpointStorage;

    // Mock storage structures for testing
    Checkpoints.UserCheckpointStorage internal userStorage;
    Checkpoints.GlobalCheckpointStorage internal globalStorage;

    // Test addresses
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    
    // Test constants
    uint256 internal constant AMOUNT = 1000 * 10**18;
    uint256 internal constant WEEK = 7 days;
    
    function setUp() public {
        // Initialize global checkpoint
        Checkpoints.initializeGlobalPoint(globalStorage);
    }
    
    // =============================================================
    //                  WEEK ROUNDING TESTS
    // =============================================================
    
    function testTimestampFloorToWeek() public {
        // Unix epoch (Jan 1, 1970) was a Thursday at 00:00 UTC
        // So week boundaries occur every Thursday at 00:00 UTC
        // Dec 31, 2020 00:00 UTC is a Thursday (week boundary)
        uint256 weekStart = 1609372800; // Thursday Dec 31, 2020 00:00 UTC (week boundary)
        uint256 midWeek = weekStart + 3 days + 12 hours; // Sunday 12:00
        
        uint256 roundedWeekStart = Checkpoints.timestampFloorToWeek(weekStart);
        uint256 roundedMidWeek = Checkpoints.timestampFloorToWeek(midWeek);
        
        assertEq(roundedWeekStart, weekStart, "Week start should not change");
        assertEq(roundedMidWeek, weekStart, "Mid-week should round down to week start");
        
        // Test that any time during the week rounds to the same start
        for (uint256 i = 0; i < 7; i++) {
            uint256 dayInWeek = weekStart + (i * 1 days) + (i * 3600); // Add some hours too
            uint256 rounded = Checkpoints.timestampFloorToWeek(dayInWeek);
            assertEq(rounded, weekStart, "All times in week should round to same start");
        }
    }
    
    // =============================================================
    //                  BINARY SEARCH TESTS
    // =============================================================
    
    function testFindUserTimestampEpochEmptyHistory() public {
        uint256 epoch = Checkpoints.findUserTimestampEpoch(userStorage, alice, vm.getBlockTimestamp());
        assertEq(epoch, 0, "Empty history should return epoch 0");
    }
    
    function testFindUserTimestampEpochSinglePoint() public {
        // Add a single point for Alice
        uint256 testTime = vm.getBlockTimestamp();
        userStorage.userPointHistory[alice][1] = Checkpoints.Point({
            bias: 1000e18,
            slope: 48116,
            updatedAt: testTime,
            amount: 1000e18
        });
        userStorage.userPointEpoch[alice] = 1;
        
        // Query before the point
        uint256 epochBefore = Checkpoints.findUserTimestampEpoch(userStorage, alice, testTime - 1);
        assertEq(epochBefore, 0, "Should return 0 for timestamp before first point");
        
        // Query at the point
        uint256 epochAt = Checkpoints.findUserTimestampEpoch(userStorage, alice, testTime);
        assertEq(epochAt, 1, "Should return correct epoch for exact timestamp");
        
        // Query after the point
        uint256 epochAfter = Checkpoints.findUserTimestampEpoch(userStorage, alice, testTime + 1000);
        assertEq(epochAfter, 1, "Should return latest epoch for future timestamp");
    }
    
    function testFindUserTimestampEpochMultiplePoints() public {
        // Add multiple points for Alice
        uint256 time1 = vm.getBlockTimestamp();
        uint256 time2 = time1 + 1 weeks;
        uint256 time3 = time2 + 2 weeks;
        
        userStorage.userPointHistory[alice][1] = Checkpoints.Point({
            bias: 1000e18, slope: 48116, updatedAt: time1, amount: 1000e18
        });
        userStorage.userPointHistory[alice][2] = Checkpoints.Point({
            bias: 1500e18, slope: 72174, updatedAt: time2, amount: 1500e18
        });
        userStorage.userPointHistory[alice][3] = Checkpoints.Point({
            bias: 2000e18, slope: 96232, updatedAt: time3, amount: 2000e18
        });
        userStorage.userPointEpoch[alice] = 3;
        
        // Test binary search finds correct epochs
        assertEq(Checkpoints.findUserTimestampEpoch(userStorage, alice, time1 - 1), 0);
        assertEq(Checkpoints.findUserTimestampEpoch(userStorage, alice, time1), 1);
        assertEq(Checkpoints.findUserTimestampEpoch(userStorage, alice, time1 + 1), 1);
        assertEq(Checkpoints.findUserTimestampEpoch(userStorage, alice, time2 - 1), 1);
        assertEq(Checkpoints.findUserTimestampEpoch(userStorage, alice, time2), 2);
        assertEq(Checkpoints.findUserTimestampEpoch(userStorage, alice, time3), 3);
        assertEq(Checkpoints.findUserTimestampEpoch(userStorage, alice, time3 + 1000), 3);
    }
    
    function testFindTimestampEpochGlobal() public {
        // Test global timestamp finding with initialized point
        uint256 epoch = Checkpoints.findTimestampEpoch(globalStorage, vm.getBlockTimestamp());
        assertEq(epoch, 0, "Should find initial global point");
        
        // Add another global point
        uint256 time1 = vm.getBlockTimestamp() + 1 weeks;
        globalStorage.globalPointHistory[1] = Checkpoints.Point({
            bias: 1000e18, slope: 48116, updatedAt: time1, amount: 1000e18
        });
        globalStorage.globalPointEpoch = 1;
        
        // Test finding points
        assertEq(Checkpoints.findTimestampEpoch(globalStorage, time1 - 1), 0);
        assertEq(Checkpoints.findTimestampEpoch(globalStorage, time1), 1);
        assertEq(Checkpoints.findTimestampEpoch(globalStorage, time1 + 1), 1);
    }
    
    // =============================================================
    //                  STORAGE ACCESS TESTS
    // =============================================================
    
    function testGetUserPoint() public {
        // Add a point for Alice
        Checkpoints.Point memory testPoint = Checkpoints.Point({
            bias: 1000e18,
            slope: 48116,
            updatedAt: vm.getBlockTimestamp(),
            amount: 1000e18
        });
        
        userStorage.userPointHistory[alice][5] = testPoint;
        
        Checkpoints.Point memory retrieved = Checkpoints.getUserPoint(userStorage, alice, 5);
        assertEq(retrieved.bias, testPoint.bias, "Bias should match");
        assertEq(retrieved.slope, testPoint.slope, "Slope should match");
        assertEq(retrieved.updatedAt, testPoint.updatedAt, "UpdatedAt should match");
        assertEq(retrieved.amount, testPoint.amount, "Amount should match");
    }
    
    function testGetGlobalPoint() public {
        Checkpoints.Point memory retrieved = Checkpoints.getGlobalPoint(globalStorage, 0);
        assertEq(retrieved.bias, 0, "Initial global point bias should be 0");
        assertEq(retrieved.slope, 0, "Initial global point slope should be 0");
        assertEq(retrieved.updatedAt, vm.getBlockTimestamp(), "Initial global point should have current timestamp");
        assertEq(retrieved.amount, 0, "Initial global point amount should be 0");
    }
    
    function testGetUserEpoch() public {
        userStorage.userPointEpoch[alice] = 42;
        uint256 epoch = Checkpoints.getUserEpoch(userStorage, alice);
        assertEq(epoch, 42, "Should return correct user epoch");
    }
    
    function testGetGlobalEpoch() public {
        globalStorage.globalPointEpoch = 123;
        uint256 epoch = Checkpoints.getGlobalEpoch(globalStorage);
        assertEq(epoch, 123, "Should return correct global epoch");
    }
    
    // =============================================================
    //                  CHECKPOINT INTEGRATION TESTS
    // =============================================================
    
    function testCheckpointNewLock() public {
        // Create a new lock
        Checkpoints.LockInfo memory emptyLock;
        Checkpoints.LockInfo memory newLock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S / 2
        });
        
        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyLock, newLock);
        
        // Verify user checkpoint was created
        assertEq(userStorage.userPointEpoch[alice], 1, "User epoch should be 1");
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][1];
        assertEq(userPoint.amount, AMOUNT, "User point amount should match");
        assertGt(userPoint.bias, 0, "User point should have positive bias");
        assertGt(userPoint.slope, 0, "User point should have positive slope");
        
        // Verify global checkpoint was updated
        assertEq(globalStorage.globalPointEpoch, 1, "Global epoch should be 1");
        Checkpoints.Point memory globalPoint = globalStorage.globalPointHistory[1];
        assertEq(globalPoint.amount, AMOUNT, "Global point amount should match");
        assertGt(globalPoint.bias, 0, "Global point should have positive bias");
        assertGt(globalPoint.slope, 0, "Global point should have positive slope");
        
        // Verify slope change was scheduled
        int128 slopeChange = globalStorage.slopeChanges[newLock.lockEnd];
        assertLt(slopeChange, 0, "Slope change should be negative (decay scheduled)");
    }
    
    function testCheckpointTopUp() public {
        // First create a lock
        Checkpoints.LockInfo memory emptyLock;
        Checkpoints.LockInfo memory initialLock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S / 2
        });
        
        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyLock, initialLock);

        Checkpoints.Point memory globalPoint1 = globalStorage.globalPointHistory[1];
        assertEq(globalPoint1.amount, AMOUNT, "Global point amount should be the initial amount");

        // Now top up the lock
        Checkpoints.LockInfo memory topUpLock = Checkpoints.LockInfo({
            amount: AMOUNT * 2, // Double the amount
            lockEnd: initialLock.lockEnd // Same end time
        });
        
        Checkpoints.checkpoint(userStorage, globalStorage, alice, initialLock, topUpLock);
        
        // Verify user checkpoint was updated
        assertEq(userStorage.userPointEpoch[alice], 2, "User epoch should be 2");
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][2];
        assertEq(userPoint.amount, AMOUNT * 2, "User point amount should be doubled");
        
        // Verify global checkpoint reflects the change (should have merged the changes to a single global)
        assertEq(globalStorage.globalPointEpoch, 1, "Global epoch should be 1");
        Checkpoints.Point memory globalPoint2 = globalStorage.globalPointHistory[1];
        assertEq(globalPoint2.amount, AMOUNT * 2, "Global point amount should be doubled");
    }
    
    function testCheckpointExtendLock() public {
        // First create a lock
        uint256 initialEnd = vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S / 4;
        uint256 extendedEnd = vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S / 2;
        
        Checkpoints.LockInfo memory emptyLock;
        Checkpoints.LockInfo memory initialLock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: initialEnd
        });
        
        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyLock, initialLock);
        
        // Extend the lock
        Checkpoints.LockInfo memory extendedLock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: extendedEnd
        });
        
        Checkpoints.checkpoint(userStorage, globalStorage, alice, initialLock, extendedLock);
        
        // Verify slope changes were updated
        int128 oldSlopeChange = globalStorage.slopeChanges[initialEnd];
        int128 newSlopeChange = globalStorage.slopeChanges[extendedEnd];
        
        assertEq(oldSlopeChange, 0, "Old slope change should be cancelled");
        assertLt(newSlopeChange, 0, "New slope change should be scheduled");
    }
    
    function testCheckpointExpiredLock() public {
        // Create a lock that's already expired
        Checkpoints.LockInfo memory emptyLock;
        Checkpoints.LockInfo memory expiredLock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: vm.getBlockTimestamp() - 1 // Already expired
        });
        
        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyLock, expiredLock);
        
        // Verify user checkpoint has amount but no voting power
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][1];
        assertEq(userPoint.amount, AMOUNT, "Expired lock should track amount");
        assertEq(userPoint.bias, 0, "Expired lock should have 0 bias");
        assertEq(userPoint.slope, 0, "Expired lock should have 0 slope");
        
        // Verify no slope change was scheduled (since already expired)
        int128 slopeChange = globalStorage.slopeChanges[expiredLock.lockEnd];
        assertEq(slopeChange, 0, "No slope change should be scheduled for expired lock");
    }
    
    function testCheckpointBurnLock() public {
        // First create a lock
        Checkpoints.LockInfo memory emptyLock;
        Checkpoints.LockInfo memory lock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S / 2
        });
        
        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyLock, lock);
        
        // Now burn it (set to empty)
        Checkpoints.checkpoint(userStorage, globalStorage, alice, lock, emptyLock);
        
        // Verify user checkpoint was zeroed
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][2];
        assertEq(userPoint.amount, 0, "Burned lock should have 0 amount");
        assertEq(userPoint.bias, 0, "Burned lock should have 0 bias");
        assertEq(userPoint.slope, 0, "Burned lock should have 0 slope");
        
        // Verify global checkpoint was updated
        Checkpoints.Point memory globalPoint = globalStorage.globalPointHistory[2];
        assertEq(globalPoint.amount, 0, "Global amount should be 0 after burn");
    }
    
    // =============================================================
    //                  EDGE CASE TESTS
    // =============================================================
    
    function testCheckpointSameBlock() public {
        console.log("block timestamp", vm.getBlockTimestamp());
        // Create two locks in the same block
        Checkpoints.LockInfo memory emptyLock;
        Checkpoints.LockInfo memory lock1 = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S / 2
        });
        Checkpoints.LockInfo memory lock2 = Checkpoints.LockInfo({
            amount: AMOUNT * 2,
            lockEnd: vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S / 2
        });
        
        // First checkpoint
        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyLock, lock1);
        uint256 globalEpochAfterFirst = globalStorage.globalPointEpoch;
        
        // Second checkpoint in same block (different user)
        Checkpoints.checkpoint(userStorage, globalStorage, bob, emptyLock, lock2);
        uint256 globalEpochAfterSecond = globalStorage.globalPointEpoch;
        
        // Global epoch should not increment for same-block checkpoints
        assertEq(globalEpochAfterSecond, globalEpochAfterFirst, "Global epoch should not increment in same block");
        
        // But both user epochs should increment
        assertEq(userStorage.userPointEpoch[alice], 1, "Alice epoch should be 1");
        assertEq(userStorage.userPointEpoch[bob], 1, "Bob epoch should be 1");
        
        // Global point should reflect both users
        Checkpoints.Point memory globalPoint = globalStorage.globalPointHistory[globalEpochAfterSecond];
        assertEq(globalPoint.amount, AMOUNT * 3, "Global amount should be sum of both locks");
    }
    
    function testCheckpointWeeklyBackfill() public {
        // Create initial global point
        uint256 weekStart = Checkpoints.timestampFloorToWeek(vm.getBlockTimestamp());
        globalStorage.globalPointHistory[1] = Checkpoints.Point({
            bias: 1000e18,
            slope: 48116,
            updatedAt: weekStart,
            amount: 1000e18
        });
        globalStorage.globalPointEpoch = 1;
        
        // Jump ahead 3 weeks and create a new checkpoint
        vm.warp(weekStart + 3 * WEEK);
        
        Checkpoints.LockInfo memory emptyLock;
        Checkpoints.LockInfo memory newLock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S / 2
        });
        
        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyLock, newLock);
        
        // Should have backfilled weekly points
        uint256 finalEpoch = globalStorage.globalPointEpoch;
        assertGe(finalEpoch, 4, "Should have backfilled at least 3 weeks + current");
        
        // Check that backfilled points exist
        for (uint256 i = 2; i <= finalEpoch - 1; i++) {
            Checkpoints.Point memory point = globalStorage.globalPointHistory[i];
            assertGt(point.updatedAt, weekStart, "Backfilled point should have later timestamp");
            assertLe(point.updatedAt, vm.getBlockTimestamp(), "Backfilled point should not exceed current time");
        }
    }
}