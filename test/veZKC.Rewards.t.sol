// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./veZKC.t.sol";

contract veZKCRewardsTest is veZKCTest {
    uint256 constant ADD_AMOUNT = 5_000 * 10**18;
    
    function testBasicRewardPower() public {
        // Alice stakes for half max time
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        
        // Reward power should equal staked amount
        uint256 rewardPower = veToken.getRewards(alice);
        assertEq(rewardPower, AMOUNT, "Reward power should equal staked amount");
        
        // Verify it matches the staked amount from getStakedAmountAndExpiry
        (uint256 stakedAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(rewardPower, stakedAmount, "Reward power should match staked amount");
    }

    function testRewardPowerDoesNotDecay() public {
        // Alice stakes for a moderate duration
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 4);
        
        // Initial reward power
        uint256 initialRewardPower = veToken.getRewards(alice);
        assertEq(initialRewardPower, AMOUNT, "Initial reward power should equal staked amount");
        
        // Fast forward halfway through the lock period
        vm.warp(vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 8);
        
        // Reward power should remain the same (doesn't decay)
        uint256 halfwayRewardPower = veToken.getRewards(alice);
        assertEq(halfwayRewardPower, AMOUNT, "Reward power should not decay over time");
        assertEq(halfwayRewardPower, initialRewardPower, "Reward power should remain constant");
        
        // Voting power should have decayed for comparison
        uint256 votingPower = veToken.getVotes(alice);
        assertLt(votingPower, AMOUNT, "Voting power should have decayed");
    }

    function testRewardPowerWithExpiredLock() public {
        // Alice stakes with minimum duration
        vm.prank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, 0);
        
        // Get lock end
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Reward power before expiry
        uint256 rewardPowerBeforeExpiry = veToken.getRewards(alice);
        assertEq(rewardPowerBeforeExpiry, AMOUNT, "Reward power should equal staked amount before expiry");
        
        // Let the lock expire
        vm.warp(lockEnd + 1);
        
        // Reward power should STILL equal staked amount (doesn't depend on lock expiry)
        uint256 rewardPowerAfterExpiry = veToken.getRewards(alice);
        assertEq(rewardPowerAfterExpiry, AMOUNT, "Reward power should remain after stake lockup expiry");
        assertEq(rewardPowerAfterExpiry, rewardPowerBeforeExpiry, "Reward power should not change on expiry");
        
        // Voting power should be 0 after expiry for comparison
        uint256 votingPowerAfterExpiry = veToken.getVotes(alice);
        assertEq(votingPowerAfterExpiry, 0, "Voting power should be 0 after expiry");
    }

    function testRewardPowerWithAddToStake() public {
        // Initial stake
        vm.startPrank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        
        // Initial reward power
        uint256 initialRewardPower = veToken.getRewards(alice);
        assertEq(initialRewardPower, AMOUNT, "Initial reward power should equal initial stake");
        
        // Add to stake
        veToken.addToStake(ADD_AMOUNT);
        vm.stopPrank();
        
        // Reward power should increase by the added amount
        uint256 updatedRewardPower = veToken.getRewards(alice);
        assertEq(updatedRewardPower, AMOUNT + ADD_AMOUNT, "Reward power should increase with added stake");
    }

    function testCannotAddToExpiredStake() public {
        // Initial stake with minimum duration
        vm.startPrank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, 0);
        vm.stopPrank();
        
        // Get lock end and let it expire
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        vm.warp(lockEnd + 1);
        
        // Verify position is expired
        assertEq(veToken.getVotes(alice), 0, "Voting power should be 0 for expired lock");
        assertEq(veToken.getRewards(alice), AMOUNT, "Reward power should remain for expired lock");
        
        // Try to add to expired stake - should fail
        vm.prank(alice);
        vm.expectRevert("Cannot add to expired position");
        veToken.addToStake(ADD_AMOUNT);
        
        // Verify no change in amounts
        uint256 rewardPowerAfterFailedAdd = veToken.getRewards(alice);
        assertEq(rewardPowerAfterFailedAdd, AMOUNT, "Reward power should not change after failed add");
    }

    function testRewardPowerWithLockExtension() public {
        // Stake with minimum duration
        vm.prank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, 0);
        
        uint256 rewardPowerBeforeExtension = veToken.getRewards(alice);
        assertEq(rewardPowerBeforeExtension, AMOUNT, "Reward power before extension");
        
        // Extend the lock
        vm.prank(alice);
        veToken.extendStakeLockup(vm.getBlockTimestamp() + MAX_STAKE_TIME_S);
        
        // Reward power should remain the same (amount doesn't change)
        uint256 rewardPowerAfterExtension = veToken.getRewards(alice);
        assertEq(rewardPowerAfterExtension, AMOUNT, "Reward power should remain same after extension");
        assertEq(rewardPowerAfterExtension, rewardPowerBeforeExtension, "Extension shouldn't change reward power");
    }

    function testRewardPowerAfterUnstaking() public {
        // Stake with minimum duration
        vm.prank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, 0);
        
        // Reward power before unstaking
        uint256 rewardPowerBeforeUnstake = veToken.getRewards(alice);
        assertEq(rewardPowerBeforeUnstake, AMOUNT, "Should have reward power before unstaking");
        
        // Let lock expire and unstake
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        vm.warp(lockEnd + 1);
        
        vm.prank(alice);
        veToken.unstake();
        
        // After unstaking, reward power should be 0 (no active position)
        uint256 rewardPowerAfterUnstake = veToken.getRewards(alice);
        assertEq(rewardPowerAfterUnstake, 0, "Reward power should be 0 after unstaking");
    }

    function testTotalRewardPowerWithMultipleUsers() public {
        // Alice stakes
        vm.startPrank(alice);
        
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        // Bob stakes different amount
        uint256 bobAmount = AMOUNT * 2;
        vm.startPrank(bob);
        
        veToken.stake(bobAmount, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 4);
        vm.stopPrank();
        
        // Charlie stakes
        vm.startPrank(charlie);
        
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 8);
        vm.stopPrank();
        
        // Check individual reward powers
        assertEq(veToken.getRewards(alice), AMOUNT, "Alice reward power");
        assertEq(veToken.getRewards(bob), bobAmount, "Bob reward power");
        assertEq(veToken.getRewards(charlie), AMOUNT, "Charlie reward power");
        
        // Total reward power should be sum of all stakes
        uint256 totalRewardPower = veToken.getTotalRewards();
        uint256 expectedTotal = AMOUNT + bobAmount + AMOUNT;
        assertEq(totalRewardPower, expectedTotal, "Total reward power should be sum of all stakes");
    }

    function testTotalRewardPowerWithExpiredLocks() public {
        // Alice stakes with short duration
        vm.startPrank(alice);
        
        veToken.stake(AMOUNT, 0); // Minimum duration
        vm.stopPrank();
        
        // Bob stakes with longer duration
        vm.startPrank(bob);
        
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S);
        vm.stopPrank();
        
        uint256 totalBeforeExpiry = veToken.getTotalRewards();
        assertEq(totalBeforeExpiry, AMOUNT * 2, "Total should include both stakes before expiry");
        
        // Let Alice's lock expire
        (, uint256 aliceLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        vm.warp(aliceLockEnd + 1);
        
        // Total should still include Alice's stake (expired but not unstaked)
        uint256 totalAfterAliceExpiry = veToken.getTotalRewards();
        assertEq(totalAfterAliceExpiry, AMOUNT * 2, "Total should still include expired stakes");
        
        // Alice unstakes
        vm.prank(alice);
        veToken.unstake();
        
        // Now total should only include Bob's stake
        uint256 totalAfterAliceUnstake = veToken.getTotalRewards();
        assertEq(totalAfterAliceUnstake, AMOUNT, "Total should exclude unstaked amounts");
    }

    function testGetPastRewards() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        // Alice stakes at t0
        vm.prank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        
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
        assertEq(currentRewardPower, AMOUNT + ADD_AMOUNT, "Current reward power should be full amount");
        
        // Past reward power queries
        uint256 pastRewardsBeforeT0 = veToken.getPastRewards(alice, t0 - 1);
        uint256 pastRewardsAfterT0 = veToken.getPastRewards(alice, t0);
        uint256 pastRewardsAtT1 = veToken.getPastRewards(alice, t1);
        uint256 pastRewardsAtT2 = veToken.getPastRewards(alice, t2 - 1);
        assertEq(pastRewardsBeforeT0, 0, "Should have 0 reward power before staking");
        assertEq(pastRewardsAfterT0, AMOUNT, "Should have initial amount before adding");
        assertEq(pastRewardsAtT1, AMOUNT + ADD_AMOUNT, "Should have full amount after adding");
        assertEq(pastRewardsAtT2, AMOUNT + ADD_AMOUNT, "Should have full amount after adding");
    }

    function testGetPastTotalRewards() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        // Alice stakes
        vm.startPrank(alice);
        
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        vm.warp(t0 + 1000);
        uint256 t1 = vm.getBlockTimestamp();
        
        // Bob stakes
        vm.startPrank(bob);
        
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        vm.warp(t1 + 1000);
        uint256 t2 = vm.getBlockTimestamp();
        
        // Current total should be both stakes
        uint256 currentTotalRewards = veToken.getTotalRewards();
        assertEq(currentTotalRewards, AMOUNT * 2, "Current total should be both stakes");
        
        uint256 pastTotalBeforeT0 = veToken.getPastTotalRewards(t0 - 1);
        uint256 pastTotalAtT0 = veToken.getPastTotalRewards(t0);
        uint256 pastTotalAtT1 = veToken.getPastTotalRewards(t1);
        assertEq(pastTotalBeforeT0, 0, "Should have 0 total before any stakes");
        assertEq(pastTotalAtT0, AMOUNT, "Should have Alice's stake after staking");
        assertEq(pastTotalAtT1, AMOUNT * 2, "Should have Alice's stake before Bob joined");
    }

    function testPreDeploymentTimestamps() public {
        // Test behavior with timestamps before deployment
        uint256 deploymentTime = vm.getBlockTimestamp();
        uint256 preDeploymentTime = deploymentTime - 1000; // 1000 seconds before deployment
        
        // Test getPastRewards before any activity
        uint256 pastRewardsPreDeployment = veToken.getPastRewards(alice, preDeploymentTime);
        assertEq(pastRewardsPreDeployment, 0, "Should return 0 for pre-deployment timestamps");
        
        // Test getPastVotes before any activity  
        uint256 pastVotesPreDeployment = veToken.getPastVotes(alice, preDeploymentTime);
        assertEq(pastVotesPreDeployment, 0, "Should return 0 for pre-deployment timestamps");
        
        // Test getPastTotalRewards before any activity
        uint256 pastTotalRewardsPreDeployment = veToken.getPastTotalRewards(preDeploymentTime);
        assertEq(pastTotalRewardsPreDeployment, 0, "Should return 0 for pre-deployment timestamps");
        
        // Test getPastTotalSupply before any activity
        uint256 pastTotalSupplyPreDeployment = veToken.getPastTotalSupply(preDeploymentTime);
        assertEq(pastTotalSupplyPreDeployment, 0, "Should return 0 for pre-deployment timestamps");
        
        // Test edge case: just before deployment time (before any stakes)
        uint256 pastRewardsAtDeployment = veToken.getPastRewards(alice, deploymentTime - 1);
        assertEq(pastRewardsAtDeployment, 0, "Should return 0 just before deployment time");
        
        uint256 pastVotesAtDeployment = veToken.getPastVotes(alice, deploymentTime - 1);
        assertEq(pastVotesAtDeployment, 0, "Should return 0 just before deployment time");
        
        // Test with timestamp = 0 (extreme edge case)
        uint256 pastRewardsAtZero = veToken.getPastRewards(alice, 0);
        assertEq(pastRewardsAtZero, 0, "Should return 0 for timestamp 0");
        
        uint256 pastVotesAtZero = veToken.getPastVotes(alice, 0);
        assertEq(pastVotesAtZero, 0, "Should return 0 for timestamp 0");
        
        // Now do some activity and test again
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        
        // Move forward in time
        vm.warp(vm.getBlockTimestamp() + 1000);
        
        // Pre-deployment timestamps should still return 0
        pastRewardsPreDeployment = veToken.getPastRewards(alice, preDeploymentTime);
        assertEq(pastRewardsPreDeployment, 0, "Should still return 0 for pre-deployment timestamps after staking");
        
        pastVotesPreDeployment = veToken.getPastVotes(alice, preDeploymentTime);
        assertEq(pastVotesPreDeployment, 0, "Should still return 0 for pre-deployment timestamps after staking");
        
        pastTotalRewardsPreDeployment = veToken.getPastTotalRewards(preDeploymentTime);
        assertEq(pastTotalRewardsPreDeployment, 0, "Should still return 0 for pre-deployment total rewards");
        
        pastTotalSupplyPreDeployment = veToken.getPastTotalSupply(preDeploymentTime);
        assertEq(pastTotalSupplyPreDeployment, 0, "Should still return 0 for pre-deployment total supply");
    }

    function testRewardPowerWithComplexFlow() public {
        // 1. Alice stakes
        vm.startPrank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, 0);
        vm.stopPrank();
        
        assertEq(veToken.getRewards(alice), AMOUNT, "Initial reward power");
        
        // 2. Let lock expire
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        vm.warp(lockEnd + 1);
        
        // Reward power should remain (doesn't care about expiry)
        assertEq(veToken.getRewards(alice), AMOUNT, "Reward power should remain after expiry");
        assertEq(veToken.getVotes(alice), 0, "Voting power should be 0 after expiry");
        
        // 3. Try to add to expired stake (should fail)
        vm.prank(alice);
        vm.expectRevert("Cannot add to expired position");
        veToken.addToStake(ADD_AMOUNT);
        
        // 4. Extend lock first to re-activate position
        vm.prank(alice);
        veToken.extendStakeLockup(vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        
        // Voting power should be restored after extension
        assertGt(veToken.getVotes(alice), 0, "Voting power should be restored after extension");
        assertEq(veToken.getRewards(alice), AMOUNT, "Reward power should remain same after extension");
        
        // 5. Now we can add to the re-activated position
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);
        
        // Reward power should increase
        assertEq(veToken.getRewards(alice), AMOUNT + ADD_AMOUNT, "Reward power should increase after adding to re-activated stake");
        assertGt(veToken.getVotes(alice), 0, "Voting power should remain positive");
        
        // 6. Eventually unstake
        (, uint256 newLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        vm.warp(newLockEnd + 1);
        
        vm.prank(alice);
        veToken.unstake();
        
        // Now both should be 0
        assertEq(veToken.getRewards(alice), 0, "Reward power should be 0 after unstaking");
        assertEq(veToken.getVotes(alice), 0, "Voting power should be 0 after unstaking");
    }
    
    function testRewardsTimepointValidation() public {
        // Alice stakes first
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
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
        
        assertEq(pastRewards, AMOUNT, "Past rewards should equal staked amount");
        assertEq(pastTotalRewards, AMOUNT, "Past total rewards should equal total staked");
    }
}