// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./veZKC.t.sol";

contract veZKCVotesTest is veZKCTest {
    uint256 constant WEEK = 1 weeks;
    
    // Test 1: getVotes returns properly decayed amounts over time
    function testGetVotesDecaysOverTime() public {
        // Alice stakes for 52 weeks (half of max time)
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        // Get actual expiry time using getStakedAmountAndExpiry
        (uint256 stakedAmount, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(stakedAmount, AMOUNT, "Staked amount should match");
        
        uint256 lockDuration = lockEnd - block.timestamp;
        
        // Initial voting power should be AMOUNT * lockDuration / MAXTIME
        uint256 initialPower = veToken.getVotes(alice);
        uint256 expectedInitial = AMOUNT * lockDuration / MAX_STAKE_TIME_S;
        assertApproxEqRel(initialPower, expectedInitial, 0.01e18, "Initial power incorrect");
        
        // After 26 weeks, remaining time should be ~26 weeks
        vm.warp(block.timestamp + 26 weeks);
        uint256 halfTimePower = veToken.getVotes(alice);
        uint256 remainingTime = lockEnd - block.timestamp;
        uint256 expectedHalf = AMOUNT * remainingTime / MAX_STAKE_TIME_S;
        assertApproxEqRel(halfTimePower, expectedHalf, 0.01e18, "Half-time power incorrect");
        
        // After lock expires, power should be 0
        vm.warp(lockEnd);
        uint256 expiredPower = veToken.getVotes(alice);
        assertEq(expiredPower, 0, "Expired lock should have 0 power");
    }
    
    // Test 2: getPastVotes returns correct historical values
    function testGetPastVotesHistoricalAccuracy() public {
        // Record initial timestamp
        uint256 t0 = block.timestamp;
        
        // Alice stakes at t0 for 104 weeks (max time for full power)
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 104 weeks);
        
        // Get actual expiry using getStakedAmountAndExpiry
        (, uint256 aliceLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Move forward and record checkpoints
        vm.warp(t0 + 10 weeks);
        uint256 t1 = block.timestamp;
        
        vm.warp(t0 + 20 weeks);
        uint256 t2 = block.timestamp;
        
        // Bob stakes at t2 for 52 weeks
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        vm.warp(t0 + 30 weeks);
        
        // Query historical values
        uint256 alicePowerAtT1 = veToken.getPastVotes(alice, t1);
        uint256 aliceRemainingAtT1 = aliceLockEnd - t1;
        uint256 expectedAtT1 = AMOUNT * aliceRemainingAtT1 / MAX_STAKE_TIME_S;
        assertApproxEqRel(alicePowerAtT1, expectedAtT1, 0.01e18, "Historical power at t1 incorrect");
        
        uint256 alicePowerAtT2 = veToken.getPastVotes(alice, t2);
        uint256 aliceRemainingAtT2 = aliceLockEnd - t2;
        uint256 expectedAtT2 = AMOUNT * aliceRemainingAtT2 / MAX_STAKE_TIME_S;
        assertApproxEqRel(alicePowerAtT2, expectedAtT2, 0.01e18, "Historical power at t2 incorrect");
        
        // Bob should have 0 power at t1 (before staking)
        uint256 bobPowerAtT1 = veToken.getPastVotes(bob, t1);
        assertEq(bobPowerAtT1, 0, "Bob should have 0 power before staking");
    }
    
    // Test 3: getTotalVotes with multiple users and decay
    function testGetTotalVotesWithDecay() public {
        // Multiple users stake at different times
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 104 weeks); // Max time
        
        (, uint256 aliceLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        uint256 totalAfterAlice = veToken.getTotalVotes();
        assertApproxEqRel(totalAfterAlice, AMOUNT, 0.01e18, "Total after Alice incorrect");
        
        vm.warp(block.timestamp + 10 weeks);
        
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + 52 weeks); // Half max time
        
        (, uint256 bobLockEnd) = veToken.getStakedAmountAndExpiry(bob);
        
        // Total should be Alice's decayed + Bob's initial
        uint256 aliceRemaining = aliceLockEnd - block.timestamp;
        uint256 bobRemaining = bobLockEnd - block.timestamp;
        uint256 aliceDecayed = AMOUNT * aliceRemaining / MAX_STAKE_TIME_S;
        uint256 bobInitial = AMOUNT * bobRemaining / MAX_STAKE_TIME_S;
        uint256 expectedTotal = aliceDecayed + bobInitial;
        
        uint256 totalAfterBob = veToken.getTotalVotes();
        assertApproxEqRel(totalAfterBob, expectedTotal, 0.01e18, "Total after Bob incorrect");
        
        // Fast forward to when Bob's lock expires
        vm.warp(bobLockEnd);
        
        // Only Alice should have remaining power
        uint256 aliceRemainingAtBobExpiry = aliceLockEnd - block.timestamp;
        uint256 aliceExpectedPower = AMOUNT * aliceRemainingAtBobExpiry / MAX_STAKE_TIME_S;
        uint256 totalAtBobExpiry = veToken.getTotalVotes();
        assertApproxEqRel(totalAtBobExpiry, aliceExpectedPower, 0.01e18, "Total at Bob expiry incorrect");
    }
    
    // Test 4: Slope changes are properly scheduled and applied
    function testSlopeChangesAtExpiry() public {
        // Alice stakes for 8 weeks
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 8 weeks);
        
        (, uint256 aliceExpiry) = veToken.getStakedAmountAndExpiry(alice);
        
        // Bob stakes for 12 weeks  
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + 12 weeks);
        
        (, uint256 bobExpiry) = veToken.getStakedAmountAndExpiry(bob);
        
        // Check slope changes are scheduled
        int128 aliceSlopeChange = veToken.slopeChanges(aliceExpiry);
        int128 bobSlopeChange = veToken.slopeChanges(bobExpiry);
        
        // Slope changes should be positive (making global slope less negative)
        assertTrue(aliceSlopeChange > 0, "Alice slope change should be positive");
        assertTrue(bobSlopeChange > 0, "Bob slope change should be positive");
        
        // Move to just before Alice expiry
        vm.warp(aliceExpiry - 1);
        uint256 totalBeforeExpiry = veToken.getTotalVotes();
        
        // Move past Alice expiry
        vm.warp(aliceExpiry + 1);
        uint256 totalAfterExpiry = veToken.getTotalVotes();
        
        // Total should decrease after expiry (Bob's power only)
        assertTrue(totalAfterExpiry < totalBeforeExpiry, "Total should decrease after expiry");
    }
    
    // Test 5: Adding to stake updates voting power correctly
    function testAddToStakeUpdatesVotingPower() public {
        // Alice stakes initially
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        uint256 initialPower = veToken.getVotes(alice);
        
        // Move forward 10 weeks
        vm.warp(block.timestamp + 10 weeks);
        
        uint256 decayedPower = veToken.getVotes(alice);
        assertLt(decayedPower, initialPower, "Power should decay over time");
        
        // Add more stake
        vm.prank(alice);
        veToken.addToStake(tokenId, AMOUNT);
        
        // Get updated amount after adding stake
        (uint256 updatedAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(updatedAmount, AMOUNT * 2, "Amount should be doubled");
        
        // Power should increase but still be based on remaining time
        uint256 afterAddPower = veToken.getVotes(alice);
        uint256 remainingTime = lockEnd - block.timestamp;
        uint256 expectedPower = (AMOUNT * 2) * remainingTime / MAX_STAKE_TIME_S;
        assertApproxEqRel(afterAddPower, expectedPower, 0.01e18, "Power after add incorrect");
    }
    
    // Test 6: Lock extension updates voting power and slopes
    function testLockExtensionUpdatesVotingPower() public {
        // Alice stakes for minimum time (4 weeks)
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + 4 weeks);
        
        (, uint256 initialLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        uint256 initialPower = veToken.getVotes(alice);
        uint256 initialDuration = initialLockEnd - block.timestamp;
        uint256 expectedInitial = AMOUNT * initialDuration / MAX_STAKE_TIME_S;
        assertApproxEqRel(initialPower, expectedInitial, 0.01e18, "Initial 4-week power incorrect");
        
        // Extend lock to 52 weeks total
        vm.prank(alice);
        uint256 newLockEndTime = block.timestamp + 52 weeks;
        veToken.extendLockToTime(tokenId, newLockEndTime);
        
        (, uint256 extendedLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        uint256 extendedDuration = extendedLockEnd - block.timestamp;
        
        uint256 extendedPower = veToken.getVotes(alice);
        uint256 expectedExtended = AMOUNT * extendedDuration / MAX_STAKE_TIME_S;
        assertApproxEqRel(extendedPower, expectedExtended, 0.01e18, "Extended power incorrect");
        
        // Check slope change is updated
        int128 slopeChange = veToken.slopeChanges(extendedLockEnd);
        assertTrue(slopeChange > 0, "Extended slope change should be scheduled");
    }
    
    // Test 7: Ensure votes can't go negative
    function testVotesNeverNegative() public {
        // Stake and let it expire
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 4 weeks);
        
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Move well past expiry
        vm.warp(lockEnd + 10 weeks);
        
        uint256 expiredVotes = veToken.getVotes(alice);
        assertEq(expiredVotes, 0, "Expired votes should be 0, not negative");
        
        uint256 totalVotes = veToken.getTotalVotes();
        assertEq(totalVotes, 0, "Total votes should be 0 when all expired");
    }
    
    // Test 8: getPastTotalSupply returns historical total voting power
    function testGetPastTotalSupply() public {
        uint256 t0 = block.timestamp;
        
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 104 weeks);
        
        (, uint256 aliceLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        vm.warp(t0 + 10 weeks);
        uint256 t1 = block.timestamp;
        
        // Bob stakes
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        (, uint256 bobLockEnd) = veToken.getStakedAmountAndExpiry(bob);
        
        vm.warp(t0 + 20 weeks);
        uint256 t2 = block.timestamp;
        
        // Check historical total supply
        uint256 totalAtT1 = veToken.getPastTotalSupply(t1);
        uint256 aliceRemainingAtT1 = aliceLockEnd - t1;
        uint256 expectedT1 = AMOUNT * aliceRemainingAtT1 / MAX_STAKE_TIME_S; // Only Alice
        assertApproxEqRel(totalAtT1, expectedT1, 0.01e18, "Total supply at t1 incorrect");
        
        uint256 totalAtT2 = veToken.getPastTotalSupply(t2);
        uint256 aliceRemainingAtT2 = aliceLockEnd - t2;
        uint256 bobRemainingAtT2 = bobLockEnd - t2;
        uint256 aliceAtT2 = AMOUNT * aliceRemainingAtT2 / MAX_STAKE_TIME_S;
        uint256 bobAtT2 = AMOUNT * bobRemainingAtT2 / MAX_STAKE_TIME_S;
        uint256 expectedT2 = aliceAtT2 + bobAtT2;
        assertApproxEqRel(totalAtT2, expectedT2, 0.01e18, "Total supply at t2 incorrect");
    }
    
    // Test 9: Voting power with different lock durations
    function testVotingPowerWithDifferentLockDurations() public {
        // Alice stakes for max time (104 weeks)
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 104 weeks);
        
        // Bob stakes for half max time (52 weeks)
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        // Charlie stakes for quarter max time (26 weeks)
        vm.prank(charlie);
        veToken.stake(AMOUNT, block.timestamp + 26 weeks);
        
        // Get actual lock ends
        (, uint256 aliceEnd) = veToken.getStakedAmountAndExpiry(alice);
        (, uint256 bobEnd) = veToken.getStakedAmountAndExpiry(bob);
        (, uint256 charlieEnd) = veToken.getStakedAmountAndExpiry(charlie);
        
        uint256 alicePower = veToken.getVotes(alice);
        uint256 bobPower = veToken.getVotes(bob);
        uint256 charliePower = veToken.getVotes(charlie);
        
        // Calculate expected powers
        uint256 aliceDuration = aliceEnd - block.timestamp;
        uint256 bobDuration = bobEnd - block.timestamp;
        uint256 charlieDuration = charlieEnd - block.timestamp;
        
        uint256 expectedAlice = AMOUNT * aliceDuration / MAX_STAKE_TIME_S;
        uint256 expectedBob = AMOUNT * bobDuration / MAX_STAKE_TIME_S;
        uint256 expectedCharlie = AMOUNT * charlieDuration / MAX_STAKE_TIME_S;
        
        assertApproxEqRel(alicePower, expectedAlice, 0.01e18, "Alice power incorrect");
        assertApproxEqRel(bobPower, expectedBob, 0.01e18, "Bob power incorrect");
        assertApproxEqRel(charliePower, expectedCharlie, 0.01e18, "Charlie power incorrect");
        
        // Alice should have more power than Bob, Bob more than Charlie
        assertTrue(alicePower > bobPower, "Alice should have more power than Bob");
        assertTrue(bobPower > charliePower, "Bob should have more power than Charlie");
    }
}