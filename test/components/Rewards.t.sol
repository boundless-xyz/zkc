// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../veZKC.t.sol";
import "../../src/interfaces/IStaking.sol";
import "../../src/libraries/Constants.sol";
import "../../src/libraries/StakeManager.sol";

contract veZKCRewardsTest is veZKCTest {
    uint256 constant ADD_AMOUNT = 5_000 * 10 ** 18;

    function testBasicRewardPower() public {
        // Alice stakes
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);

        // Reward power should equal staked amount divided by scalar
        uint256 rewardPower = veToken.getStakingRewards(alice);
        vm.snapshotGasLastCall("getRewards: Getting current reward power");
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardPower, expectedPower, "Reward power should equal staked amount divided by scalar");

        // Verify it matches the staked amount from getStakedAmountAndWithdrawalTime
        (uint256 stakedAmount,) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(
            rewardPower,
            stakedAmount / Constants.REWARD_POWER_SCALAR,
            "Reward power should match calculation from staked amount"
        );
    }

    function testRewardPowerDoesNotDecay() public {
        // Alice stakes
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);

        // Initial reward power
        uint256 initialRewardPower = veToken.getStakingRewards(alice);
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(initialRewardPower, expectedPower, "Initial reward power should equal staked amount divided by scalar");

        // Fast forward time
        vm.warp(vm.getBlockTimestamp() + 52 weeks);

        // Reward power should remain the same (doesn't decay)
        uint256 laterRewardPower = veToken.getStakingRewards(alice);
        assertEq(laterRewardPower, expectedPower, "Reward power should not decay over time");
        assertEq(laterRewardPower, initialRewardPower, "Reward power should remain constant");

        // Voting power should also remain the same (no decay in withdrawal system)
        uint256 votingPower = veToken.getVotes(alice);
        assertEq(
            votingPower,
            AMOUNT / Constants.VOTING_POWER_SCALAR,
            "Voting power should also remain constant in withdrawal system"
        );
    }

    function testRewardPowerWithWithdrawal() public {
        // Alice stakes
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);

        // Reward power before withdrawal
        uint256 rewardPowerBeforeWithdrawal = veToken.getStakingRewards(alice);
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(
            rewardPowerBeforeWithdrawal, expectedPower, "Reward power should equal staked amount before withdrawal"
        );

        // Initiate withdrawal
        vm.prank(alice);
        veToken.initiateUnstake();

        // Reward power should immediately drop to 0 when withdrawing
        uint256 rewardPowerDuringWithdrawal = veToken.getStakingRewards(alice);
        assertEq(rewardPowerDuringWithdrawal, 0, "Reward power should be 0 during withdrawal period");

        // Even after time passes during withdrawal period, should remain 0
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD / 2);
        uint256 rewardPowerMidWithdrawal = veToken.getStakingRewards(alice);
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
        uint256 initialRewardPower = veToken.getStakingRewards(alice);
        uint256 expectedInitial = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(
            initialRewardPower, expectedInitial, "Initial reward power should equal initial stake divided by scalar"
        );

        // Add to stake
        veToken.addToStake(ADD_AMOUNT);
        vm.stopPrank();

        // Reward power should increase by the added amount
        uint256 updatedRewardPower = veToken.getStakingRewards(alice);
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
        uint256 rewardPowerAfterFailedAdd = veToken.getStakingRewards(alice);
        assertEq(rewardPowerAfterFailedAdd, 0, "Reward power should remain 0 after failed add to withdrawing position");
    }

    function testRewardPowerAfterCompleteUnstake() public {
        // Stake
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);

        // Reward power before unstaking
        uint256 rewardPowerBeforeUnstake = veToken.getStakingRewards(alice);
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardPowerBeforeUnstake, expectedPower, "Should have reward power before unstaking");

        // Complete withdrawal workflow
        vm.startPrank(alice);
        veToken.initiateUnstake();
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);
        veToken.completeUnstake();
        vm.stopPrank();

        // After unstaking, reward power should be 0 (no active position)
        uint256 rewardPowerAfterUnstake = veToken.getStakingRewards(alice);
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

        assertEq(veToken.getStakingRewards(alice), aliceExpected, "Alice reward power");
        assertEq(veToken.getStakingRewards(bob), bobExpected, "Bob reward power");
        assertEq(veToken.getStakingRewards(charlie), charlieExpected, "Charlie reward power");

        // Total reward power should be sum of all stakes divided by scalar
        uint256 totalRewardPower = veToken.getTotalStakingRewards();
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

        uint256 totalBeforeWithdrawal = veToken.getTotalStakingRewards();
        uint256 expectedBefore = (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR;
        assertEq(totalBeforeWithdrawal, expectedBefore, "Total should include both stakes before withdrawal");

        // Alice initiates withdrawal
        vm.prank(alice);
        veToken.initiateUnstake();

        // Total should now only include Bob's stake
        uint256 totalAfterAliceWithdrawal = veToken.getTotalStakingRewards();
        uint256 expectedAfter = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(totalAfterAliceWithdrawal, expectedAfter, "Total should exclude withdrawing stakes");

        // Alice completes unstaking
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);
        vm.prank(alice);
        veToken.completeUnstake();

        // Total should still only include Bob's stake
        uint256 totalAfterAliceUnstake = veToken.getTotalStakingRewards();
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
        uint256 currentRewardPower = veToken.getStakingRewards(alice);
        uint256 expectedCurrent = (AMOUNT + ADD_AMOUNT) / Constants.REWARD_POWER_SCALAR;
        assertEq(currentRewardPower, expectedCurrent, "Current reward power should be full amount divided by scalar");

        // Past reward power queries
        uint256 pastRewardsAfterT0 = veToken.getPastStakingRewards(alice, t0);
        vm.snapshotGasLastCall("getPastRewards: Getting historical reward power");
        uint256 pastRewardsAtT1 = veToken.getPastStakingRewards(alice, t1);

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
        uint256 currentTotalRewards = veToken.getTotalStakingRewards();
        uint256 expectedCurrent = (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR;
        assertEq(currentTotalRewards, expectedCurrent, "Current total should be both stakes divided by scalar");

        uint256 pastTotalAtT0 = veToken.getPastTotalStakingRewards(t0);
        vm.snapshotGasLastCall("getPastTotalRewards: Getting historical total reward power");
        uint256 pastTotalAtT1 = veToken.getPastTotalStakingRewards(t1);

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
        uint256 pastRewardsPreDeployment = veToken.getPastStakingRewards(alice, preDeploymentTime);
        assertEq(pastRewardsPreDeployment, 0, "Should return 0 for pre-deployment timestamps");

        // Test getPastTotalRewards before any activity
        uint256 pastTotalRewardsPreDeployment = veToken.getPastTotalStakingRewards(preDeploymentTime);
        assertEq(pastTotalRewardsPreDeployment, 0, "Should return 0 for pre-deployment timestamps");

        // Test edge case: just before deployment time (before any stakes)
        uint256 pastRewardsAtDeployment = veToken.getPastStakingRewards(alice, deploymentTime - 1);
        assertEq(pastRewardsAtDeployment, 0, "Should return 0 just before deployment time");

        // Test with timestamp = 0 (extreme edge case)
        uint256 pastRewardsAtZero = veToken.getPastStakingRewards(alice, 0);
        assertEq(pastRewardsAtZero, 0, "Should return 0 for timestamp 0");

        // Now do some activity and test again
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);

        // Move forward in time
        vm.warp(vm.getBlockTimestamp() + 1000);

        // Pre-deployment timestamps should still return 0
        pastRewardsPreDeployment = veToken.getPastStakingRewards(alice, preDeploymentTime);
        assertEq(pastRewardsPreDeployment, 0, "Should still return 0 for pre-deployment timestamps after staking");

        pastTotalRewardsPreDeployment = veToken.getPastTotalStakingRewards(preDeploymentTime);
        assertEq(pastTotalRewardsPreDeployment, 0, "Should still return 0 for pre-deployment total rewards");
    }

    function testRewardPowerWithComplexWithdrawalFlow() public {
        // 1. Alice stakes
        vm.startPrank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);
        vm.stopPrank();

        uint256 expectedInitial = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getStakingRewards(alice), expectedInitial, "Initial reward power");

        // 2. Alice initiates withdrawal
        vm.prank(alice);
        veToken.initiateUnstake();

        // Reward power should immediately drop to 0
        assertEq(veToken.getStakingRewards(alice), 0, "Reward power should be 0 during withdrawal");
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
        assertEq(veToken.getStakingRewards(alice), 0, "Reward power should be 0 after unstaking");
        assertEq(veToken.getVotes(alice), 0, "Voting power should be 0 after unstaking");

        // 5. Alice can stake again with a new position (she still has ADD_AMOUNT allowance remaining)
        vm.prank(alice);
        uint256 newTokenId = veToken.stake(ADD_AMOUNT);

        // Should get reward power based on new stake amount
        uint256 expectedNew = ADD_AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getStakingRewards(alice), expectedNew, "Should have reward power based on new stake amount");
        assertEq(
            veToken.getVotes(alice),
            ADD_AMOUNT / Constants.VOTING_POWER_SCALAR,
            "Should have voting power based on new stake amount"
        );
    }

    function testRewardsTimepointValidation() public {
        // Alice stakes first
        vm.startPrank(alice);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        uint256 currentTime = vm.getBlockTimestamp();

        // Test that calling getPastRewards with current timestamp reverts
        vm.expectRevert();
        veToken.getPastStakingRewards(alice, currentTime);

        // Test that calling getPastTotalRewards with current timestamp reverts
        vm.expectRevert();
        veToken.getPastTotalStakingRewards(currentTime);

        // Test that calling with future timestamp reverts
        vm.expectRevert();
        veToken.getPastStakingRewards(alice, currentTime + 1);

        vm.expectRevert();
        veToken.getPastTotalStakingRewards(currentTime + 1);

        // Test that calling with past timestamp works
        vm.warp(currentTime + 1000);

        uint256 pastRewards = veToken.getPastStakingRewards(alice, currentTime);
        uint256 pastTotalRewards = veToken.getPastTotalStakingRewards(currentTime);

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
        uint256 rewardsAfterStake = veToken.getStakingRewards(alice);
        uint256 expectedInitial = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(
            rewardsAfterStake,
            expectedInitial,
            "Rewards after initial stake should equal initial amount divided by scalar"
        );

        // Perform second action in same block: add to stake
        // Note: We don't warp time, so this happens in the same block
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);

        // Verify final state after both actions
        uint256 rewardsAfterAdd = veToken.getStakingRewards(alice);
        uint256 expectedFinal = (AMOUNT + ADD_AMOUNT) / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardsAfterAdd, expectedFinal, "Rewards after adding should equal total amount divided by scalar");

        // The key test: move to next block and query historical rewards for the action block
        vm.warp(actionTimestamp + 1);

        // When querying rewards for the block where both actions happened,
        // binary search should return the FINAL state (after both stake and addToStake)
        uint256 historicalRewards = veToken.getPastStakingRewards(alice, actionTimestamp);
        assertEq(
            historicalRewards,
            expectedFinal,
            "Historical rewards should reflect final state after all actions in the block"
        );

        // Should NOT equal the intermediate state after just the initial stake
        assertTrue(historicalRewards != expectedInitial, "Historical rewards should not return intermediate state");

        // Verify total rewards also reflects final state
        uint256 historicalTotalRewards = veToken.getPastTotalStakingRewards(actionTimestamp);
        assertEq(historicalTotalRewards, expectedFinal, "Historical total rewards should reflect final state");
    }

    function testRewardPowerScaling() public {
        // Test that reward power scales correctly with the scalar
        // Reward power = staked amount / REWARD_POWER_SCALAR

        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        // Reward power should equal staked amount divided by scalar
        uint256 rewardPower = veToken.getStakingRewards(alice);
        uint256 expectedPower = AMOUNT / Constants.REWARD_POWER_SCALAR;
        assertEq(rewardPower, expectedPower, "Reward power should equal staked amount divided by REWARD_POWER_SCALAR");
    }

    function testZeroRewardPowerWhenNoStake() public {
        // User with no stake should have 0 reward power
        assertEq(veToken.getStakingRewards(alice), 0, "Alice should have 0 reward power without stake");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have 0 reward power without stake");

        // Historical rewards should also be 0 - warp forward first
        uint256 currentTime = vm.getBlockTimestamp();
        vm.warp(currentTime + 1);
        assertEq(veToken.getPastStakingRewards(alice, currentTime), 0, "Historical rewards should be 0 without stake");
        assertEq(veToken.getPastStakingRewards(bob, currentTime), 0, "Historical rewards should be 0 without stake");
    }

    function testBasicPoVWRewardCap() public {
        // Alice stakes
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);

        // PoVW cap should equal staked amount divided by POVW_REWARD_CAP_SCALAR
        uint256 povwCap = veToken.getPoVWRewardCap(alice);
        vm.snapshotGasLastCall("getPoVWRewardCap: Getting current PoVW cap");
        uint256 expectedCap = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(povwCap, expectedCap, "PoVW cap should equal staked amount divided by POVW_REWARD_CAP_SCALAR");

        // Verify it's different from staking rewards
        uint256 stakingRewards = veToken.getStakingRewards(alice);
        assertEq(
            stakingRewards, AMOUNT / Constants.REWARD_POWER_SCALAR, "Staking rewards should use REWARD_POWER_SCALAR"
        );

        // The relationship between staking rewards and PoVW cap is determined by the scalars
        // Note: due to integer division, there may be a rounding error of 1
        uint256 expectedMultiplier = Constants.POVW_REWARD_CAP_SCALAR / Constants.REWARD_POWER_SCALAR;
        assertApproxEqAbs(
            stakingRewards,
            povwCap * expectedMultiplier,
            1,
            "Staking rewards should be approximately POVW_REWARD_CAP_SCALAR/REWARD_POWER_SCALAR times the PoVW cap"
        );
    }

    function testPoVWRewardCapDoesNotDecay() public {
        // Alice stakes
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);

        // Initial PoVW cap
        uint256 initialCap = veToken.getPoVWRewardCap(alice);
        uint256 expectedCap = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(initialCap, expectedCap, "Initial PoVW cap should equal staked amount divided by POVW scalar");

        // Fast forward time
        vm.warp(vm.getBlockTimestamp() + 52 weeks);

        // PoVW cap should remain the same (doesn't decay)
        uint256 laterCap = veToken.getPoVWRewardCap(alice);
        assertEq(laterCap, expectedCap, "PoVW cap should not decay over time");
        assertEq(laterCap, initialCap, "PoVW cap should remain constant");
    }

    function testPoVWRewardCapWithWithdrawal() public {
        // Alice stakes
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);

        // PoVW cap before withdrawal
        uint256 capBeforeWithdrawal = veToken.getPoVWRewardCap(alice);
        uint256 expectedCap = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(capBeforeWithdrawal, expectedCap, "PoVW cap should equal staked amount before withdrawal");

        // Initiate withdrawal
        vm.prank(alice);
        veToken.initiateUnstake();

        // PoVW cap should immediately drop to 0 when withdrawing
        uint256 capDuringWithdrawal = veToken.getPoVWRewardCap(alice);
        assertEq(capDuringWithdrawal, 0, "PoVW cap should be 0 during withdrawal period");

        // Even after time passes during withdrawal period, should remain 0
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD / 2);
        uint256 capMidWithdrawal = veToken.getPoVWRewardCap(alice);
        assertEq(capMidWithdrawal, 0, "PoVW cap should remain 0 throughout withdrawal period");
    }

    function testPoVWRewardCapWithAddToStake() public {
        // Initial stake
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT + ADD_AMOUNT);
        uint256 tokenId = veToken.stake(AMOUNT);

        // Initial PoVW cap
        uint256 initialCap = veToken.getPoVWRewardCap(alice);
        uint256 expectedInitial = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(initialCap, expectedInitial, "Initial PoVW cap should equal initial stake divided by POVW scalar");

        // Add to stake
        veToken.addToStake(ADD_AMOUNT);
        vm.stopPrank();

        // PoVW cap should increase by the added amount
        uint256 updatedCap = veToken.getPoVWRewardCap(alice);
        uint256 expectedUpdated = (AMOUNT + ADD_AMOUNT) / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(updatedCap, expectedUpdated, "PoVW cap should increase with added stake");
    }

    function testGetPastPoVWRewardCap() public {
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

        // Current PoVW cap should be full amount
        uint256 currentCap = veToken.getPoVWRewardCap(alice);
        uint256 expectedCurrent = (AMOUNT + ADD_AMOUNT) / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(currentCap, expectedCurrent, "Current PoVW cap should be full amount divided by POVW scalar");

        // Past PoVW cap queries
        uint256 pastCapAfterT0 = veToken.getPastPoVWRewardCap(alice, t0);
        vm.snapshotGasLastCall("getPastPoVWRewardCap: Getting historical PoVW cap");
        uint256 pastCapAtT1 = veToken.getPastPoVWRewardCap(alice, t1);

        uint256 expectedInitial = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        uint256 expectedAfterAdd = (AMOUNT + ADD_AMOUNT) / Constants.POVW_REWARD_CAP_SCALAR;

        assertEq(pastCapAfterT0, expectedInitial, "Should have initial amount after staking");
        assertEq(pastCapAtT1, expectedAfterAdd, "Should have full amount after adding");
    }

    function testPoVWCapTimepointValidation() public {
        // Alice stakes first
        vm.startPrank(alice);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        uint256 currentTime = vm.getBlockTimestamp();

        // Test that calling getPastPoVWRewardCap with current timestamp reverts
        vm.expectRevert();
        veToken.getPastPoVWRewardCap(alice, currentTime);

        // Test that calling with future timestamp reverts
        vm.expectRevert();
        veToken.getPastPoVWRewardCap(alice, currentTime + 1);

        // Test that calling with past timestamp works
        vm.warp(currentTime + 1000);

        uint256 pastCap = veToken.getPastPoVWRewardCap(alice, currentTime);
        uint256 expectedCap = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(pastCap, expectedCap, "Past PoVW cap should equal staked amount divided by POVW scalar");
    }

    function testZeroPoVWCapWhenNoStake() public {
        // User with no stake should have 0 PoVW cap
        assertEq(veToken.getPoVWRewardCap(alice), 0, "Alice should have 0 PoVW cap without stake");
        assertEq(veToken.getPoVWRewardCap(bob), 0, "Bob should have 0 PoVW cap without stake");

        // Historical PoVW cap should also be 0 - warp forward first
        uint256 currentTime = vm.getBlockTimestamp();
        vm.warp(currentTime + 1);
        assertEq(veToken.getPastPoVWRewardCap(alice, currentTime), 0, "Historical PoVW cap should be 0 without stake");
        assertEq(veToken.getPastPoVWRewardCap(bob, currentTime), 0, "Historical PoVW cap should be 0 without stake");
    }

    function testCompareStakingRewardsVsPoVWCap() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Get both values
        uint256 stakingRewards = veToken.getStakingRewards(alice);
        uint256 povwCap = veToken.getPoVWRewardCap(alice);

        // Verify scalars are applied correctly
        assertEq(
            stakingRewards,
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Staking rewards should equal amount divided by REWARD_POWER_SCALAR"
        );
        assertEq(
            povwCap,
            AMOUNT / Constants.POVW_REWARD_CAP_SCALAR,
            "PoVW cap should equal amount divided by POVW_REWARD_CAP_SCALAR"
        );

        // Relationship check - the scalars maintain the expected relationship
        // stakingRewards = AMOUNT / REWARD_POWER_SCALAR
        // povwCap = AMOUNT / POVW_REWARD_CAP_SCALAR
        // Therefore: stakingRewards * POVW_REWARD_CAP_SCALAR = povwCap * REWARD_POWER_SCALAR * (POVW_REWARD_CAP_SCALAR / REWARD_POWER_SCALAR)
        assertEq(
            stakingRewards / povwCap,
            Constants.POVW_REWARD_CAP_SCALAR / Constants.REWARD_POWER_SCALAR,
            "Ratio of rewards to cap should equal ratio of scalars"
        );
    }

    function testPoVWCapComplexWithdrawalFlow() public {
        // 1. Alice stakes
        vm.startPrank(alice);
        uint256 tokenId = veToken.stake(AMOUNT);
        vm.stopPrank();

        uint256 expectedInitial = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(veToken.getPoVWRewardCap(alice), expectedInitial, "Initial PoVW cap");

        // 2. Alice initiates withdrawal
        vm.prank(alice);
        veToken.initiateUnstake();

        // PoVW cap should immediately drop to 0
        assertEq(veToken.getPoVWRewardCap(alice), 0, "PoVW cap should be 0 during withdrawal");

        // 3. Complete withdrawal after waiting period
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);
        vm.prank(alice);
        veToken.completeUnstake();

        // Now both should be 0 (no active position)
        assertEq(veToken.getPoVWRewardCap(alice), 0, "PoVW cap should be 0 after unstaking");

        // 4. Alice can stake again with a new position
        vm.prank(alice);
        uint256 newTokenId = veToken.stake(ADD_AMOUNT);

        // Should get PoVW cap based on new stake amount
        uint256 expectedNew = ADD_AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(veToken.getPoVWRewardCap(alice), expectedNew, "Should have PoVW cap based on new stake amount");
    }
}
