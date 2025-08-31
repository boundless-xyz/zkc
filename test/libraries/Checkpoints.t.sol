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
        // Directly access global storage instead of using removed getGlobalPoint function
        Checkpoints.Point memory point = globalStorage.globalPointHistory[0];
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

    function testCheckpointDelta() public {
        // Test adding voting and reward power
        Checkpoints.checkpointDelta(userStorage, globalStorage, alice, int256(AMOUNT), int256(AMOUNT));

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

        // Test removing some power
        Checkpoints.checkpointDelta(userStorage, globalStorage, alice, -int256(AMOUNT / 2), -int256(AMOUNT / 4));

        // Verify updated user checkpoint
        assertEq(userStorage.userPointEpoch[alice], 2, "User epoch should be 2");
        Checkpoints.Point memory updatedUserPoint = userStorage.userPointHistory[alice][2];
        assertEq(updatedUserPoint.votingAmount, AMOUNT / 2, "User voting amount should be reduced");
        assertEq(updatedUserPoint.rewardAmount, AMOUNT * 3 / 4, "User reward amount should be reduced");

        // Verify updated global checkpoint
        assertEq(globalStorage.globalPointEpoch, 1, "Global epoch should still be 1 (same block)");
        Checkpoints.Point memory updatedGlobalPoint = globalStorage.globalPointHistory[1];
        assertEq(updatedGlobalPoint.votingAmount, AMOUNT / 2, "Global voting amount should be reduced");
        assertEq(updatedGlobalPoint.rewardAmount, AMOUNT * 3 / 4, "Global reward amount should be reduced");
    }

    function testCheckpointVoteDelegation() public {
        // Give alice some initial power
        Checkpoints.checkpointDelta(userStorage, globalStorage, alice, int256(AMOUNT), int256(AMOUNT));
        
        // Test vote delegation - should only affect voting power
        Checkpoints.checkpointVoteDelegation(userStorage, alice, int256(AMOUNT / 2));

        // Verify user checkpoint was updated
        assertEq(userStorage.userPointEpoch[alice], 2, "User epoch should be 2");
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][2];
        assertEq(userPoint.votingAmount, AMOUNT + AMOUNT / 2, "Voting amount should increase");
        assertEq(userPoint.rewardAmount, AMOUNT, "Reward amount should stay the same");
        assertEq(userPoint.updatedAt, block.timestamp, "User point should have current timestamp");

        // Test negative delegation (removing delegated votes)
        Checkpoints.checkpointVoteDelegation(userStorage, alice, -int256(AMOUNT));

        // Verify updated user checkpoint
        assertEq(userStorage.userPointEpoch[alice], 3, "User epoch should be 3");
        Checkpoints.Point memory updatedUserPoint = userStorage.userPointHistory[alice][3];
        assertEq(updatedUserPoint.votingAmount, AMOUNT / 2, "Voting amount should decrease");
        assertEq(updatedUserPoint.rewardAmount, AMOUNT, "Reward amount should still stay the same");
    }

    function testCheckpointRewardDelegation() public {
        // Give alice some initial power
        Checkpoints.checkpointDelta(userStorage, globalStorage, alice, int256(AMOUNT), int256(AMOUNT));
        
        // Test reward delegation - should only affect reward power
        Checkpoints.checkpointRewardDelegation(userStorage, alice, int256(AMOUNT / 3));

        // Verify user checkpoint was updated
        assertEq(userStorage.userPointEpoch[alice], 2, "User epoch should be 2");
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][2];
        assertEq(userPoint.votingAmount, AMOUNT, "Voting amount should stay the same");
        assertEq(userPoint.rewardAmount, AMOUNT + AMOUNT / 3, "Reward amount should increase");
        assertEq(userPoint.updatedAt, block.timestamp, "User point should have current timestamp");

        // Test negative delegation (removing delegated rewards)
        Checkpoints.checkpointRewardDelegation(userStorage, alice, -int256(AMOUNT / 2));

        // Verify updated user checkpoint
        assertEq(userStorage.userPointEpoch[alice], 3, "User epoch should be 3");
        Checkpoints.Point memory updatedUserPoint = userStorage.userPointHistory[alice][3];
        assertEq(updatedUserPoint.votingAmount, AMOUNT, "Voting amount should still stay the same");
        assertEq(updatedUserPoint.rewardAmount, AMOUNT + AMOUNT / 3 - AMOUNT / 2, "Reward amount should decrease");
    }

    function testCheckpointWithDelegation() public {
        Checkpoints.StakeInfo memory emptyStake;
        Checkpoints.StakeInfo memory newStake = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});

        // Test with no delegation
        (int256 votingDelta, int256 rewardDelta) = Checkpoints.checkpointWithDelegation(
            userStorage, globalStorage, alice, emptyStake, newStake, false, false
        );

        assertEq(votingDelta, 0, "No voting delta should be returned when not delegated");
        assertEq(rewardDelta, 0, "No reward delta should be returned when not delegated");

        // Verify user checkpoint was created
        assertEq(userStorage.userPointEpoch[alice], 1, "User epoch should be 1");
        Checkpoints.Point memory userPoint = userStorage.userPointHistory[alice][1];
        assertEq(userPoint.votingAmount, AMOUNT, "User voting amount should equal stake");
        assertEq(userPoint.rewardAmount, AMOUNT, "User reward amount should equal stake");

        // Test with vote delegation
        Checkpoints.StakeInfo memory addedStake = Checkpoints.StakeInfo({amount: AMOUNT * 2, withdrawalRequestedAt: 0});
        (int256 votingDelta2, int256 rewardDelta2) = Checkpoints.checkpointWithDelegation(
            userStorage, globalStorage, alice, newStake, addedStake, true, false
        );

        // Votes are delegated, so we should receive a voting delta for us to apply to the delegatee
        assertEq(votingDelta2, int256(AMOUNT), "Voting delta should be returned for delegation");
        assertEq(rewardDelta2, 0, "No reward delta when rewards not delegated");

        // Verify user checkpoint - voting amount should not change since delegated
        assertEq(userStorage.userPointEpoch[alice], 2, "User epoch should be 2");
        Checkpoints.Point memory updatedUserPoint = userStorage.userPointHistory[alice][2];
        assertEq(updatedUserPoint.votingAmount, AMOUNT, "User voting amount should stay same (delegated)");
        assertEq(updatedUserPoint.rewardAmount, AMOUNT * 2, "User reward amount should increase");

        // Test with both delegations
        Checkpoints.StakeInfo memory finalStake = Checkpoints.StakeInfo({amount: AMOUNT * 3, withdrawalRequestedAt: 0});
        (int256 votingDelta3, int256 rewardDelta3) = Checkpoints.checkpointWithDelegation(
            userStorage, globalStorage, alice, addedStake, finalStake, true, true
        );

        assertEq(votingDelta3, int256(AMOUNT), "Voting delta should be returned for delegation");
        assertEq(rewardDelta3, int256(AMOUNT), "Reward delta should be returned for delegation");

        // Verify user checkpoint - neither should change since both delegated
        assertEq(userStorage.userPointEpoch[alice], 2, "User epoch should stay 2 (no checkpoint created)");
    }

    function testUpdateGlobalCheckpoint() public {
        // Test with active stake
        Checkpoints.StakeInfo memory emptyStake;
        Checkpoints.StakeInfo memory activeStake = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});

        Checkpoints.updateGlobalCheckpoint(globalStorage, emptyStake, activeStake);

        // Verify global checkpoint was updated
        assertEq(globalStorage.globalPointEpoch, 1, "Global epoch should be 1");
        Checkpoints.Point memory globalPoint = globalStorage.globalPointHistory[1];
        assertEq(globalPoint.votingAmount, AMOUNT, "Global voting amount should equal stake");
        assertEq(globalPoint.rewardAmount, AMOUNT, "Global reward amount should equal stake");

        // Test with withdrawing stake (should have 0 effective amount)
        Checkpoints.StakeInfo memory withdrawingStake = Checkpoints.StakeInfo({
            amount: AMOUNT, 
            withdrawalRequestedAt: block.timestamp
        });

        Checkpoints.updateGlobalCheckpoint(globalStorage, activeStake, withdrawingStake);

        // Verify global checkpoint was updated (same block, so should update existing epoch)
        assertEq(globalStorage.globalPointEpoch, 1, "Global epoch should still be 1 (same block)");
        Checkpoints.Point memory updatedGlobalPoint = globalStorage.globalPointHistory[1];
        assertEq(updatedGlobalPoint.votingAmount, 0, "Global voting amount should be 0 (withdrawing)");
        assertEq(updatedGlobalPoint.rewardAmount, 0, "Global reward amount should be 0 (withdrawing)");

        // Move to next block and test completing withdrawal
        vm.warp(block.timestamp + 1);
        Checkpoints.updateGlobalCheckpoint(globalStorage, withdrawingStake, emptyStake);

        // Verify new global checkpoint was created
        assertEq(globalStorage.globalPointEpoch, 2, "Global epoch should be 2 (new block)");
        Checkpoints.Point memory finalGlobalPoint = globalStorage.globalPointHistory[2];
        assertEq(finalGlobalPoint.votingAmount, 0, "Global voting amount should remain 0");
        assertEq(finalGlobalPoint.rewardAmount, 0, "Global reward amount should remain 0");
    }

    function testSameBlockCheckpointMerging() public {
        // Test that checkpoints in the same block update existing global points
        Checkpoints.checkpointDelta(userStorage, globalStorage, alice, int256(AMOUNT), int256(AMOUNT));
        uint256 globalEpochAfterFirst = globalStorage.globalPointEpoch;
        
        // Add another user in the same block
        Checkpoints.checkpointDelta(userStorage, globalStorage, bob, int256(AMOUNT * 2), int256(AMOUNT * 2));
        uint256 globalEpochAfterSecond = globalStorage.globalPointEpoch;

        // Global epoch should not increment for same-block checkpoints
        assertEq(globalEpochAfterSecond, globalEpochAfterFirst, "Global epoch should not increment in same block");
        assertEq(globalEpochAfterSecond, 1, "Global epoch should be 1");

        // But both user epochs should increment
        assertEq(userStorage.userPointEpoch[alice], 1, "Alice epoch should be 1");
        assertEq(userStorage.userPointEpoch[bob], 1, "Bob epoch should be 1");

        // Global point should reflect both users
        Checkpoints.Point memory globalPoint = globalStorage.globalPointHistory[globalEpochAfterSecond];
        assertEq(globalPoint.votingAmount, AMOUNT * 3, "Global voting amount should be sum of both stakes");
        assertEq(globalPoint.rewardAmount, AMOUNT * 3, "Global reward amount should be sum of both stakes");
    }
}