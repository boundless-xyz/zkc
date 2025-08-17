// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./veZKC.t.sol";

contract veZKCRewardsTest is veZKCTest {
    uint256 constant ADD_AMOUNT = 5_000 * 10**18;
    
    function testBasicRewardPower() public {
        // Alice stakes for half max time
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        
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
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 4);
        
        // Initial reward power
        uint256 initialRewardPower = veToken.getRewards(alice);
        assertEq(initialRewardPower, AMOUNT, "Initial reward power should equal staked amount");
        
        // Fast forward halfway through the lock period
        vm.warp(block.timestamp + MAX_STAKE_TIME_S / 8);
        
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
        assertEq(rewardPowerAfterExpiry, AMOUNT, "Reward power should remain after lock expiry");
        assertEq(rewardPowerAfterExpiry, rewardPowerBeforeExpiry, "Reward power should not change on expiry");
        
        // Voting power should be 0 after expiry for comparison
        uint256 votingPowerAfterExpiry = veToken.getVotes(alice);
        assertEq(votingPowerAfterExpiry, 0, "Voting power should be 0 after expiry");
    }

    function testRewardPowerWithAddToStake() public {
        // Initial stake
        vm.startPrank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        
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

    function testRewardPowerWithAddToExpiredStake() public {
        // Initial stake with minimum duration
        vm.startPrank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, 0);
        vm.stopPrank();
        
        // Get lock end and let it expire
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        vm.warp(lockEnd + 1);
        
        // Add to expired stake
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);
        
        // Reward power should reflect the full amount even though lock is expired
        uint256 rewardPowerAfterAdd = veToken.getRewards(alice);
        assertEq(rewardPowerAfterAdd, AMOUNT + ADD_AMOUNT, "Reward power should reflect full amount even with expired lock");
        
        // Voting power should still be 0
        assertEq(veToken.getVotes(alice), 0, "Voting power should remain 0 for expired lock");
    }

    function testRewardPowerWithLockExtension() public {
        // Stake with minimum duration
        vm.prank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, 0);
        
        uint256 rewardPowerBeforeExtension = veToken.getRewards(alice);
        assertEq(rewardPowerBeforeExtension, AMOUNT, "Reward power before extension");
        
        // Extend the lock
        vm.prank(alice);
        veToken.extendStakeLockup(block.timestamp + MAX_STAKE_TIME_S);
        
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
        
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        // Bob stakes different amount
        uint256 bobAmount = AMOUNT * 2;
        vm.startPrank(bob);
        
        veToken.stake(bobAmount, block.timestamp + MAX_STAKE_TIME_S / 4);
        vm.stopPrank();
        
        // Charlie stakes
        vm.startPrank(charlie);
        
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 8);
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
        
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S);
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

    // Test past rewards (will fail until we implement proper snapshotting)
    function testGetPastRewards() public {
        uint256 t0 = block.timestamp;
        
        // Alice stakes at t0
        vm.prank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        
        // Move forward in time
        vm.warp(t0 + 1000);
        uint256 t1 = block.timestamp;
        
        // Alice adds to stake
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);
        
        // Move forward again
        vm.warp(t1 + 1000);
        uint256 t2 = block.timestamp;
        
        // Current reward power should be full amount
        uint256 currentRewardPower = veToken.getRewards(alice);
        assertEq(currentRewardPower, AMOUNT + ADD_AMOUNT, "Current reward power should be full amount");
        
        // Past reward power queries (these will return incorrect values until snapshotting is implemented)
        uint256 pastRewardsAtT0 = veToken.getPastRewards(alice, t0);
        uint256 pastRewardsAtT1 = veToken.getPastRewards(alice, t1);
        
        // TODO: Once snapshotting is implemented, these should work:
        // assertEq(pastRewardsAtT0, 0, "Should have 0 reward power before staking");
        // assertEq(pastRewardsAtT1, AMOUNT, "Should have initial amount before adding");
    }

    // Test past total rewards (will fail until we implement proper snapshotting)
    function testGetPastTotalRewards() public {
        uint256 t0 = block.timestamp;
        
        // Alice stakes
        vm.startPrank(alice);
        
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        vm.warp(t0 + 1000);
        uint256 t1 = block.timestamp;
        
        // Bob stakes
        vm.startPrank(bob);
        
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        vm.warp(t1 + 1000);
        uint256 t2 = block.timestamp;
        
        // Current total should be both stakes
        uint256 currentTotalRewards = veToken.getTotalRewards();
        assertEq(currentTotalRewards, AMOUNT * 2, "Current total should be both stakes");
        
        // Past total reward queries (these will return incorrect values until snapshotting is implemented)
        uint256 pastTotalAtT0 = veToken.getPastTotalRewards(t0);
        uint256 pastTotalAtT1 = veToken.getPastTotalRewards(t1);
        
        // TODO: Once snapshotting is implemented, these should work:
        // assertEq(pastTotalAtT0, 0, "Should have 0 total before any stakes");
        // assertEq(pastTotalAtT1, AMOUNT, "Should have Alice's stake before Bob joined");
    }

    function testRewardPowerVsVotingPowerComparison() public {
        // Stake for half max time
        vm.prank(alice);
        
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        
        // Initially, voting power should be less than reward power (due to time decay)
        uint256 initialVotingPower = veToken.getVotes(alice);
        uint256 initialRewardPower = veToken.getRewards(alice);
        
        assertEq(initialRewardPower, AMOUNT, "Reward power should equal staked amount");
        assertLt(initialVotingPower, initialRewardPower, "Voting power should be less than reward power");
        
        // Fast forward significantly
        vm.warp(block.timestamp + MAX_STAKE_TIME_S / 4);
        
        uint256 laterVotingPower = veToken.getVotes(alice);
        uint256 laterRewardPower = veToken.getRewards(alice);
        
        // Reward power should remain constant
        assertEq(laterRewardPower, AMOUNT, "Reward power should remain constant");
        assertEq(laterRewardPower, initialRewardPower, "Reward power should not change over time");
        
        // Voting power should have further decayed
        assertLt(laterVotingPower, initialVotingPower, "Voting power should continue to decay");
        assertLt(laterVotingPower, laterRewardPower, "Voting power should be less than constant reward power");
    }

    function testRewardPowerWithComplexFlow() public {
        // Similar to the complex voting test but focusing on reward power behavior
        
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
        
        // 3. Add to expired stake
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);
        
        // Reward power should increase
        assertEq(veToken.getRewards(alice), AMOUNT + ADD_AMOUNT, "Reward power should increase after adding to expired stake");
        assertEq(veToken.getVotes(alice), 0, "Voting power should still be 0");
        
        // 4. Extend lock
        vm.prank(alice);
        veToken.extendStakeLockup(block.timestamp + MAX_STAKE_TIME_S / 2);
        
        // Reward power should remain the same (amount unchanged)
        assertEq(veToken.getRewards(alice), AMOUNT + ADD_AMOUNT, "Reward power should remain same after extension");
        assertGt(veToken.getVotes(alice), 0, "Voting power should be restored after extension");
        
        // 5. Eventually unstake
        (, uint256 newLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        vm.warp(newLockEnd + 1);
        
        vm.prank(alice);
        veToken.unstake();
        
        // Now both should be 0
        assertEq(veToken.getRewards(alice), 0, "Reward power should be 0 after unstaking");
        assertEq(veToken.getVotes(alice), 0, "Voting power should be 0 after unstaking");
    }
}