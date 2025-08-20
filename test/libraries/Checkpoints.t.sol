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
    uint256 internal constant AMOUNT = 1000 * 10 ** 18;
    uint256 internal constant WEEK = 7 days;

    function setUp() public {
        // Initialize global checkpoint
        Checkpoints.initializeGlobalPoint(globalStorage);
    }

    function testInitializeGlobalPoint() public {
        Checkpoints.Point memory point = Checkpoints.getGlobalPoint(globalStorage, 0);
        assertEq(point.votingAmount, 0, "Initial global voting amount should be 0");
        assertEq(point.rewardAmount, 0, "Initial global reward amount should be 0");
        assertEq(point.updatedAt, block.timestamp, "Initial timestamp should be block.timestamp");
    }

    function testFindUserTimestampEpochEmptyHistory() public {
        uint256 epoch = Checkpoints.findUserTimestampEpoch(userStorage, alice, vm.getBlockTimestamp());
        assertEq(epoch, 0, "Empty history should return epoch 0");
    }

    function testFindUserTimestampEpochSinglePoint() public {
        // Add a single point for Alice
        uint256 testTime = vm.getBlockTimestamp();
        userStorage.userPointHistory[alice][1] = 
            Checkpoints.Point({votingAmount: 1000e18, rewardAmount: 1000e18, updatedAt: testTime});
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

        userStorage.userPointHistory[alice][1] =
            Checkpoints.Point({votingAmount: 1000e18, rewardAmount: 1000e18, updatedAt: time1});
        userStorage.userPointHistory[alice][2] =
            Checkpoints.Point({votingAmount: 1500e18, rewardAmount: 1500e18, updatedAt: time2});
        userStorage.userPointHistory[alice][3] =
            Checkpoints.Point({votingAmount: 2000e18, rewardAmount: 2000e18, updatedAt: time3});
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
        globalStorage.globalPointHistory[1] =
            Checkpoints.Point({votingAmount: 1000e18, rewardAmount: 1000e18, updatedAt: time1});
        globalStorage.globalPointEpoch = 1;

        // Test finding points
        assertEq(Checkpoints.findTimestampEpoch(globalStorage, time1 - 1), 0);
        assertEq(Checkpoints.findTimestampEpoch(globalStorage, time1), 1);
        assertEq(Checkpoints.findTimestampEpoch(globalStorage, time1 + 1), 1);
    }

    function testGetUserPoint() public {
        // Add a point for Alice
        Checkpoints.Point memory testPoint = Checkpoints.Point({
            votingAmount: 1000e18,
            rewardAmount: 1000e18,
            updatedAt: vm.getBlockTimestamp()
        });

        userStorage.userPointHistory[alice][5] = testPoint;

        Checkpoints.Point memory retrieved = Checkpoints.getUserPoint(userStorage, alice, 5);
        assertEq(retrieved.votingAmount, testPoint.votingAmount, "Voting amount should match");
        assertEq(retrieved.rewardAmount, testPoint.rewardAmount, "Reward amount should match");
        assertEq(retrieved.updatedAt, testPoint.updatedAt, "UpdatedAt should match");
    }

    function testGetGlobalPoint() public {
        Checkpoints.Point memory retrieved = Checkpoints.getGlobalPoint(globalStorage, 0);
        assertEq(retrieved.votingAmount, 0, "Initial global point voting amount should be 0");
        assertEq(retrieved.rewardAmount, 0, "Initial global point reward amount should be 0");
        assertEq(retrieved.updatedAt, vm.getBlockTimestamp(), "Initial global point should have current timestamp");
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

    function testCheckpointNewStake() public {
        // Create a new stake
        Checkpoints.StakeInfo memory emptyStake;
        Checkpoints.StakeInfo memory newStake = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});

        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyStake, newStake);

        // Verify user checkpoint was created
        assertEq(userStorage.userPointEpoch[alice], 1, "User epoch should be 1");
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][1];
        assertEq(userPoint.votingAmount, AMOUNT, "User point voting amount should match");
        assertEq(userPoint.rewardAmount, AMOUNT, "User point reward amount should match");
        assertEq(userPoint.updatedAt, block.timestamp, "User point should have current timestamp");

        // Verify global checkpoint was updated
        assertEq(globalStorage.globalPointEpoch, 1, "Global epoch should be 1");
        Checkpoints.Point memory globalPoint = globalStorage.globalPointHistory[1];
        assertEq(globalPoint.votingAmount, AMOUNT, "Global point voting amount should match");
        assertEq(globalPoint.rewardAmount, AMOUNT, "Global point reward amount should match");
    }

    function testCheckpointAddStake() public {
        // First create a stake
        Checkpoints.StakeInfo memory emptyStake;
        Checkpoints.StakeInfo memory initialStake = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});

        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyStake, initialStake);

        Checkpoints.Point memory globalPoint1 = globalStorage.globalPointHistory[1];
        assertEq(globalPoint1.votingAmount, AMOUNT, "Global point voting amount should be the initial amount");
        assertEq(globalPoint1.rewardAmount, AMOUNT, "Global point reward amount should be the initial amount");

        // Now add to the stake (in same block)
        Checkpoints.StakeInfo memory addedStake = Checkpoints.StakeInfo({
            amount: AMOUNT * 2, // Double the amount
            withdrawalRequestedAt: 0 // Still not withdrawing
        });

        Checkpoints.checkpoint(userStorage, globalStorage, alice, initialStake, addedStake);

        // Verify user checkpoint was updated
        assertEq(userStorage.userPointEpoch[alice], 2, "User epoch should be 2");
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][2];
        assertEq(userPoint.votingAmount, AMOUNT * 2, "User point voting amount should be doubled");
        assertEq(userPoint.rewardAmount, AMOUNT * 2, "User point reward amount should be doubled");

        // Verify global checkpoint was merged (same block, so updates existing epoch)
        assertEq(globalStorage.globalPointEpoch, 1, "Global epoch should still be 1 (merged)");
        Checkpoints.Point memory globalPoint2 = globalStorage.globalPointHistory[1];
        assertEq(globalPoint2.votingAmount, AMOUNT * 2, "Global point voting amount should be doubled");
        assertEq(globalPoint2.rewardAmount, AMOUNT * 2, "Global point reward amount should be doubled");
    }

    function testCheckpointInitiateWithdrawal() public {
        // First create a stake
        Checkpoints.StakeInfo memory emptyStake;
        Checkpoints.StakeInfo memory activeStake = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});

        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyStake, activeStake);

        // Verify initial state
        Checkpoints.Point memory initialGlobalPoint = globalStorage.globalPointHistory[1];
        assertEq(initialGlobalPoint.votingAmount, AMOUNT, "Initial global voting amount should be AMOUNT");
        assertEq(initialGlobalPoint.rewardAmount, AMOUNT, "Initial global reward amount should be AMOUNT");

        // Initiate withdrawal
        Checkpoints.StakeInfo memory withdrawingStake =
            Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: vm.getBlockTimestamp()});

        Checkpoints.checkpoint(userStorage, globalStorage, alice, activeStake, withdrawingStake);

        // Verify user checkpoint shows withdrawing
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][2];
        assertEq(userPoint.votingAmount, AMOUNT, "Voting amount should remain the same");
        assertEq(userPoint.rewardAmount, AMOUNT, "Reward amount should remain the same");

        // Global amount should drop to 0 since user is withdrawing (powers = 0)
        Checkpoints.Point memory globalPoint = globalStorage.globalPointHistory[1]; // Should update same epoch in same block
    }

    function testCheckpointCompleteWithdrawal() public {
        // First create an active stake
        Checkpoints.StakeInfo memory emptyStake;
        Checkpoints.StakeInfo memory activeStake = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});

        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyStake, activeStake);

        // Verify active stake created global amount
        Checkpoints.Point memory activeGlobalPoint = globalStorage.globalPointHistory[1];
        assertEq(activeGlobalPoint.votingAmount, AMOUNT, "Active stake should create global voting amount");
        assertEq(activeGlobalPoint.rewardAmount, AMOUNT, "Active stake should create global reward amount");

        // Move to next block and initiate withdrawal
        vm.warp(vm.getBlockTimestamp() + 1);
        uint256 withdrawalTime = vm.getBlockTimestamp();

        Checkpoints.StakeInfo memory withdrawingStake =
            Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: withdrawalTime});

        // Checkpoint: active → withdrawing
        Checkpoints.checkpoint(userStorage, globalStorage, alice, activeStake, withdrawingStake);

        // Verify withdrawing state has 0 global amount
        Checkpoints.Point memory withdrawingGlobalPoint = globalStorage.globalPointHistory[2];

        // Warp forward past the withdrawal period + 1 block
        vm.warp(withdrawalTime + Constants.WITHDRAWAL_PERIOD + 1);

        // Complete withdrawal (burn)
        Checkpoints.checkpoint(userStorage, globalStorage, alice, withdrawingStake, emptyStake);

        // Verify user checkpoint was zeroed
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][3];
        assertEq(userPoint.votingAmount, 0, "Withdrawn stake should have 0 voting amount");
        assertEq(userPoint.rewardAmount, 0, "Withdrawn stake should have 0 reward amount");

        // Verify global checkpoint remains 0
        Checkpoints.Point memory globalPoint = globalStorage.globalPointHistory[3]; // New block, new epoch
        assertEq(globalPoint.votingAmount, 0, "Global voting amount should remain 0 after withdrawal");
        assertEq(globalPoint.rewardAmount, 0, "Global reward amount should remain 0 after withdrawal");
    }

    function testCheckpointSameBlock() public {
        console.log("block timestamp", vm.getBlockTimestamp());
        // Create two stakes in the same block
        Checkpoints.StakeInfo memory emptyStake;
        Checkpoints.StakeInfo memory stake1 = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});
        Checkpoints.StakeInfo memory stake2 = Checkpoints.StakeInfo({amount: AMOUNT * 2, withdrawalRequestedAt: 0});

        // First checkpoint
        Checkpoints.checkpoint(userStorage, globalStorage, alice, emptyStake, stake1);
        uint256 globalEpochAfterFirst = globalStorage.globalPointEpoch;

        // Second checkpoint in same block (different user)
        Checkpoints.checkpoint(userStorage, globalStorage, bob, emptyStake, stake2);
        uint256 globalEpochAfterSecond = globalStorage.globalPointEpoch;

        // Global epoch should not increment for same-block checkpoints
        assertEq(globalEpochAfterSecond, globalEpochAfterFirst, "Global epoch should not increment in same block");

        // But both user epochs should increment
        assertEq(userStorage.userPointEpoch[alice], 1, "Alice epoch should be 1");
        assertEq(userStorage.userPointEpoch[bob], 1, "Bob epoch should be 1");

        // Global point should reflect both users
        Checkpoints.Point memory globalPoint = globalStorage.globalPointHistory[globalEpochAfterSecond];
        assertEq(globalPoint.votingAmount, AMOUNT * 3, "Global voting amount should be sum of both stakes");
        assertEq(globalPoint.rewardAmount, AMOUNT * 3, "Global reward amount should be sum of both stakes");
    }
}
