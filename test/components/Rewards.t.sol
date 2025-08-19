// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../veZKC.t.sol";
import "../../src/interfaces/IStaking.sol";
import "../../src/libraries/Constants.sol";
import "../../src/libraries/StakeManager.sol";

contract veZKCRewardsTest is veZKCTest {
    uint256 constant ADD_AMOUNT = 5_000 * 10**18;
    
    function testBasicRewardPower() public {
        // Alice stakes
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);
        
        // Reward power should equal staked amount divided by scalar
        uint256 rewardPower = veToken.getRewards(alice);
        vm.snapshotGasLastCall("getRewards: Getting current reward power");
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardPower, expectedPower, "Reward power should equal staked amount divided by scalar");
        
        // Verify it matches the staked amount from getStakedAmountAndWithdrawalTime
        (uint256 stakedAmount,) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(rewardPower, stakedAmount / Constants.REWARD_POWER_SCALAR, "Reward power should match calculation from staked amount");
    }

    function testRewardPowerDoesNotDecay() public {
        // Alice stakes
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);
        
        // Initial reward power
        uint256 initialRewardPower = veToken.getRewards(alice);
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(initialRewardPower, expectedPower, "Initial reward power should equal staked amount divided by scalar");
        
        // Fast forward time
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        
        // Reward power should remain the same (doesn't decay)
        uint256 laterRewardPower = veToken.getRewards(alice);
        assertEq(laterRewardPower, expectedPower, "Reward power should not decay over time");
        assertEq(laterRewardPower, initialRewardPower, "Reward power should remain constant");
        
        // Voting power should also remain the same (no decay in withdrawal system)
        uint256 votingPower = veToken.getVotes(alice);
        assertEq(votingPower, AMOUNT / Constants.VOTING_POWER_SCALAR, "Voting power should also remain constant in withdrawal system");
    }

    function testRewardPowerWithWithdrawal() public {
        // Alice stakes
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);
        
        // Reward power before withdrawal
        uint256 rewardPowerBeforeWithdrawal = veToken.getRewards(alice);
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardPowerBeforeWithdrawal, expectedPower, "Reward power should equal staked amount before withdrawal");
        
        // Initiate withdrawal
        vm.prank(alice);
        veToken.initiateUnstake();
        
        // Reward power should immediately drop to 0 when withdrawing
        uint256 rewardPowerDuringWithdrawal = veToken.getRewards(alice);
        assertEq(rewardPowerDuringWithdrawal, 0, "Reward power should be 0 during withdrawal period");
        
        // Even after time passes during withdrawal period, should remain 0
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD / 2);
        uint256 rewardPowerMidWithdrawal = veToken.getRewards(alice);
        assertEq(rewardPowerMidWithdrawal, 0, "Reward power should remain 0 throughout withdrawal period");
        
        // Voting power should also be 0 during withdrawal
        uint256 votingPowerDuringWithdrawal = veToken.getVotes(alice);
        assertEq(votingPowerDuringWithdrawal, 0, "Voting power should be 0 during withdrawal");
    }

    function testRewardPowerWithAddToStake() public {
        // Initial stake
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT + ADD_AMOUNT);
        uint256 tokenId = veToken.stake(AMOUNT);
        
        // Initial reward power
        uint256 initialRewardPower = veToken.getRewards(alice);
        uint256 expectedInitial = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(initialRewardPower, expectedInitial, "Initial reward power should equal initial stake divided by scalar");
        
        // Add to stake
        veToken.addToStake(ADD_AMOUNT);
        vm.stopPrank();
        
        // Reward power should increase by the added amount
        uint256 updatedRewardPower = veToken.getRewards(alice);
        uint256 expectedUpdated = (AMOUNT + ADD_AMOUNT) / Constants.REWARD_POWER_SCALAR;
        assertEq(updatedRewardPower, expectedUpdated, "Reward power should increase with added stake");
    }

    function testCannotAddToWithdrawingPosition() public {
        // Initial stake
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT + ADD_AMOUNT);
        uint256 tokenId = veToken.stake(AMOUNT);
        
        // Initiate withdrawal
        veToken.initiateUnstake();
        
        // Try to add to withdrawing stake - should fail
        vm.expectRevert(StakeManager.CannotAddToWithdrawingPosition.selector);
        veToken.addToStake(ADD_AMOUNT);
        vm.stopPrank();
        
        // Verify no change in reward power (should remain 0)
        uint256 rewardPowerAfterFailedAdd = veToken.getRewards(alice);
        assertEq(rewardPowerAfterFailedAdd, 0, "Reward power should remain 0 after failed add to withdrawing position");
    }

    function testRewardPowerAfterCompleteUnstake() public {
        // Stake
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);
        
        // Reward power before unstaking
        uint256 rewardPowerBeforeUnstake = veToken.getRewards(alice);
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardPowerBeforeUnstake, expectedPower, "Should have reward power before unstaking");
        
        // Complete withdrawal workflow
        vm.startPrank(alice);
        veToken.initiateUnstake();
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);
        veToken.completeUnstake();
        vm.stopPrank();
        
        // After unstaking, reward power should be 0 (no active position)
        uint256 rewardPowerAfterUnstake = veToken.getRewards(alice);
        assertEq(rewardPowerAfterUnstake, 0, "Reward power should be 0 after completing unstaking");
    }

    function testTotalRewardPowerWithMultipleUsers() public {
        // Alice stakes
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();
        
        // Bob stakes different amount
        uint256 bobAmount = AMOUNT * 2;
        vm.startPrank(bob);
        zkc.approve(address(veToken), bobAmount);
        veToken.stake(bobAmount);
        vm.stopPrank();
        
        // Charlie stakes
        vm.startPrank(charlie);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();
        
        // Check individual reward powers
        uint256 aliceExpected = AMOUNT / Constants.REWARD_POWER_SCALAR;
        uint256 bobExpected = bobAmount / Constants.REWARD_POWER_SCALAR;
        uint256 charlieExpected = AMOUNT / Constants.REWARD_POWER_SCALAR;
        
        assertEq(veToken.getRewards(alice), aliceExpected, "Alice reward power");
        assertEq(veToken.getRewards(bob), bobExpected, "Bob reward power");
        assertEq(veToken.getRewards(charlie), charlieExpected, "Charlie reward power");
        
        // Total reward power should be sum of all stakes divided by scalar
        uint256 totalRewardPower = veToken.getTotalRewards();
        vm.snapshotGasLastCall("getTotalRewards: Getting total reward power");
        uint256 expectedTotal = (AMOUNT + bobAmount + AMOUNT) / Constants.REWARD_POWER_SCALAR;
        assertEq(totalRewardPower, expectedTotal, "Total reward power should be sum of all stakes divided by scalar");
    }

    function testTotalRewardPowerWithWithdrawals() public {
        // Alice and Bob stake
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();
        
        uint256 totalBeforeWithdrawal = veToken.getTotalRewards();
        uint256 expectedBefore = (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR;
        assertEq(totalBeforeWithdrawal, expectedBefore, "Total should include both stakes before withdrawal");
        
        // Alice initiates withdrawal
        vm.prank(alice);
        veToken.initiateUnstake();
        
        // Total should now only include Bob's stake
        uint256 totalAfterAliceWithdrawal = veToken.getTotalRewards();
        uint256 expectedAfter = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(totalAfterAliceWithdrawal, expectedAfter, "Total should exclude withdrawing stakes");
        
        // Alice completes unstaking
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);
        vm.prank(alice);
        veToken.completeUnstake();
        
        // Total should still only include Bob's stake
        uint256 totalAfterAliceUnstake = veToken.getTotalRewards();
        assertEq(totalAfterAliceUnstake, expectedAfter, "Total should remain same after completing unstake");
    }

    function testGetPastRewards() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        // Alice stakes at t0
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);
        
        // Move forward in time
        vm.warp(t0 + 1000);
        uint256 t1 = vm.getBlockTimestamp();
        
        // Alice adds to stake
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);
        
        // Move forward again
        vm.warp(t1 + 1000);
        uint256 t2 = vm.getBlockTimestamp();
        
        // Current reward power should be full amount
        uint256 currentRewardPower = veToken.getRewards(alice);
        uint256 expectedCurrent = (AMOUNT + ADD_AMOUNT) / Constants.REWARD_POWER_SCALAR;
        assertEq(currentRewardPower, expectedCurrent, "Current reward power should be full amount divided by scalar");
        
        // Past reward power queries
        uint256 pastRewardsAfterT0 = veToken.getPastRewards(alice, t0);
        vm.snapshotGasLastCall("getPastRewards: Getting historical reward power");
        uint256 pastRewardsAtT1 = veToken.getPastRewards(alice, t1);
        
        uint256 expectedInitial = AMOUNT / Constants.REWARD_POWER_SCALAR;
        uint256 expectedAfterAdd = (AMOUNT + ADD_AMOUNT) / Constants.REWARD_POWER_SCALAR;
        
        assertEq(pastRewardsAfterT0, expectedInitial, "Should have initial amount after staking");
        assertEq(pastRewardsAtT1, expectedAfterAdd, "Should have full amount after adding");
    }

    function testGetPastTotalRewards() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        // Alice stakes
        vm.startPrank(alice);
        veToken.stake(AMOUNT);
        vm.stopPrank();
        
        vm.warp(t0 + 1000);
        uint256 t1 = vm.getBlockTimestamp();
        
        // Bob stakes
        vm.startPrank(bob);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();
        
        vm.warp(t1 + 1000);
        uint256 t2 = vm.getBlockTimestamp();
        
        // Current total should be both stakes
        uint256 currentTotalRewards = veToken.getTotalRewards();
        uint256 expectedCurrent = (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR;
        assertEq(currentTotalRewards, expectedCurrent, "Current total should be both stakes divided by scalar");
        
        uint256 pastTotalAtT0 = veToken.getPastTotalRewards(t0);
        vm.snapshotGasLastCall("getPastTotalRewards: Getting historical total reward power");
        uint256 pastTotalAtT1 = veToken.getPastTotalRewards(t1);
        
        uint256 expectedT0 = AMOUNT / Constants.REWARD_POWER_SCALAR;
        uint256 expectedT1 = (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR;
        
        assertEq(pastTotalAtT0, expectedT0, "Should have Alice's stake at T0");
        assertEq(pastTotalAtT1, expectedT1, "Should have both stakes at T1");
    }

    function testPreDeploymentTimestamps() public {
        // Test behavior with timestamps before deployment
        uint256 deploymentTime = vm.getBlockTimestamp();
        uint256 preDeploymentTime = deploymentTime - 1000; // 1000 seconds before deployment
        
        // Test getPastRewards before any activity
        uint256 pastRewardsPreDeployment = veToken.getPastRewards(alice, preDeploymentTime);
        assertEq(pastRewardsPreDeployment, 0, "Should return 0 for pre-deployment timestamps");
        
        // Test getPastTotalRewards before any activity
        uint256 pastTotalRewardsPreDeployment = veToken.getPastTotalRewards(preDeploymentTime);
        assertEq(pastTotalRewardsPreDeployment, 0, "Should return 0 for pre-deployment timestamps");
        
        // Test edge case: just before deployment time (before any stakes)
        uint256 pastRewardsAtDeployment = veToken.getPastRewards(alice, deploymentTime - 1);
        assertEq(pastRewardsAtDeployment, 0, "Should return 0 just before deployment time");
        
        // Test with timestamp = 0 (extreme edge case)
        uint256 pastRewardsAtZero = veToken.getPastRewards(alice, 0);
        assertEq(pastRewardsAtZero, 0, "Should return 0 for timestamp 0");
        
        // Now do some activity and test again
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);
        
        // Move forward in time
        vm.warp(vm.getBlockTimestamp() + 1000);
        
        // Pre-deployment timestamps should still return 0
        pastRewardsPreDeployment = veToken.getPastRewards(alice, preDeploymentTime);
        assertEq(pastRewardsPreDeployment, 0, "Should still return 0 for pre-deployment timestamps after staking");
        
        pastTotalRewardsPreDeployment = veToken.getPastTotalRewards(preDeploymentTime);
        assertEq(pastTotalRewardsPreDeployment, 0, "Should still return 0 for pre-deployment total rewards");
    }

    function testRewardPowerWithComplexWithdrawalFlow() public {
        // 1. Alice stakes
        vm.startPrank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);
        vm.stopPrank();
        
        uint256 expectedInitial = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getRewards(alice), expectedInitial, "Initial reward power");
        
        // 2. Alice initiates withdrawal
        vm.prank(alice);
        veToken.initiateUnstake();
        
        // Reward power should immediately drop to 0
        assertEq(veToken.getRewards(alice), 0, "Reward power should be 0 during withdrawal");
        assertEq(veToken.getVotes(alice), 0, "Voting power should be 0 during withdrawal");
        
        // 3. Try to add to withdrawing stake (should fail)
        vm.prank(alice);
        vm.expectRevert(StakeManager.CannotAddToWithdrawingPosition.selector);
        veToken.addToStake(ADD_AMOUNT);
        
        // 4. Complete withdrawal after waiting period
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);
        vm.prank(alice);
        veToken.completeUnstake();
        
        // Now both should be 0 (no active position)
        assertEq(veToken.getRewards(alice), 0, "Reward power should be 0 after unstaking");
        assertEq(veToken.getVotes(alice), 0, "Voting power should be 0 after unstaking");
        
        // 5. Alice can stake again with a new position (she still has ADD_AMOUNT allowance remaining)
        vm.prank(alice);
        uint256 newTokenId = veToken.stake(ADD_AMOUNT);
        
        // Should get reward power based on new stake amount
        uint256 expectedNew = ADD_AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getRewards(alice), expectedNew, "Should have reward power based on new stake amount");
        assertEq(veToken.getVotes(alice), ADD_AMOUNT / Constants.VOTING_POWER_SCALAR, "Should have voting power based on new stake amount");
    }
    
    function testRewardsTimepointValidation() public {
        // Alice stakes first
        vm.startPrank(alice);
        veToken.stake(AMOUNT);
        vm.stopPrank();
        
        uint256 currentTime = vm.getBlockTimestamp();
        
        // Test that calling getPastRewards with current timestamp reverts
        vm.expectRevert();
        veToken.getPastRewards(alice, currentTime);
        
        // Test that calling getPastTotalRewards with current timestamp reverts
        vm.expectRevert();
        veToken.getPastTotalRewards(currentTime);
        
        // Test that calling with future timestamp reverts
        vm.expectRevert();
        veToken.getPastRewards(alice, currentTime + 1);
        
        vm.expectRevert();
        veToken.getPastTotalRewards(currentTime + 1);
        
        // Test that calling with past timestamp works
        vm.warp(currentTime + 1000);
        
        uint256 pastRewards = veToken.getPastRewards(alice, currentTime);
        uint256 pastTotalRewards = veToken.getPastTotalRewards(currentTime);
        
        uint256 expectedRewards = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(pastRewards, expectedRewards, "Past rewards should equal staked amount divided by scalar");
        assertEq(pastTotalRewards, expectedRewards, "Past total rewards should equal total staked divided by scalar");
    }

    function testMultipleRewardActionsInSameBlock() public {
        // Alice stakes initially
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT + ADD_AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();
        
        // Store current timestamp - all actions will happen in this block
        uint256 actionTimestamp = vm.getBlockTimestamp();
        
        // Verify initial state
        uint256 rewardsAfterStake = veToken.getRewards(alice);
        uint256 expectedInitial = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardsAfterStake, expectedInitial, "Rewards after initial stake should equal initial amount divided by scalar");
        
        // Perform second action in same block: add to stake
        // Note: We don't warp time, so this happens in the same block
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);
        
        // Verify final state after both actions
        uint256 rewardsAfterAdd = veToken.getRewards(alice);
        uint256 expectedFinal = (AMOUNT + ADD_AMOUNT) / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardsAfterAdd, expectedFinal, "Rewards after adding should equal total amount divided by scalar");
        
        // The key test: move to next block and query historical rewards for the action block
        vm.warp(actionTimestamp + 1);
        
        // When querying rewards for the block where both actions happened,
        // binary search should return the FINAL state (after both stake and addToStake)
        uint256 historicalRewards = veToken.getPastRewards(alice, actionTimestamp);
        assertEq(historicalRewards, expectedFinal, 
            "Historical rewards should reflect final state after all actions in the block");
        
        // Should NOT equal the intermediate state after just the initial stake
        assertTrue(historicalRewards != expectedInitial, 
            "Historical rewards should not return intermediate state");
        
        // Verify total rewards also reflects final state
        uint256 historicalTotalRewards = veToken.getPastTotalRewards(actionTimestamp);
        assertEq(historicalTotalRewards, expectedFinal,
            "Historical total rewards should reflect final state");
    }

    function testRewardPowerScaling() public {
        // Test that reward power scales correctly with the scalar
        // With REWARD_POWER_SCALAR = 1, we should get 1:1 ratio
        
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();
        
        // Reward power should equal staked amount divided by scalar (which is 1)
        uint256 rewardPower = veToken.getRewards(alice);
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardPower, expectedPower, "Reward power should equal staked amount divided by scalar");
        
        // Since scalar is 1, this should equal the full amount
        assertEq(rewardPower, AMOUNT, "Reward power should equal full amount when scalar is 1");
    }

    function testZeroRewardPowerWhenNoStake() public {
        // User with no stake should have 0 reward power
        assertEq(veToken.getRewards(alice), 0, "Alice should have 0 reward power without stake");
        assertEq(veToken.getRewards(bob), 0, "Bob should have 0 reward power without stake");
        
        // Historical rewards should also be 0 - warp forward first
        uint256 currentTime = vm.getBlockTimestamp();
        vm.warp(currentTime + 1);
        assertEq(veToken.getPastRewards(alice, currentTime), 0, "Historical rewards should be 0 without stake");
        assertEq(veToken.getPastRewards(bob, currentTime), 0, "Historical rewards should be 0 without stake");
    }
}