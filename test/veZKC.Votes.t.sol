// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./veZKC.t.sol";

contract veZKCVotesTest is veZKCTest {
    uint256 constant WEEK = 1 weeks;
    
    function _calculateExpectedVotePower(uint256 amount, uint256 curTime, uint256 lockEnd) internal view returns (uint256) {
        if (curTime >= lockEnd) return 0;
        
        uint256 remainingTime = lockEnd - curTime;
        uint256 slope = amount / MAX_STAKE_TIME_S;
        return slope * remainingTime;
    }
    
    function testGetVotesDecaysOverTime() public {
        // Alice stakes for half of max time
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        
        // Get actual expiry time using getStakedAmountAndExpiry
        (uint256 stakedAmount, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(stakedAmount, AMOUNT);
        
        // Initial voting power should match veZKC calculation
        uint256 initialPower = veToken.getVotes(alice);
        assertEq(initialPower, _calculateExpectedVotePower(AMOUNT, block.timestamp, lockEnd));
        
        // After 50% of stake time
        vm.warp(block.timestamp + MAX_STAKE_TIME_S / 4);
        uint256 halfTimePower = veToken.getVotes(alice);
        assertEq(halfTimePower, _calculateExpectedVotePower(AMOUNT, block.timestamp, lockEnd));
        
        // After lock expires, power should be 0
        vm.warp(lockEnd);
        uint256 expiredPower = veToken.getVotes(alice);
        assertEq(expiredPower, 0);
    }
    
    function testGetPastVotesHistoricalAccuracy() public {
        // Record initial timestamp
        uint256 t0 = block.timestamp;
        
        // Alice stakes at t0 for max time
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S);
        
        // Get actual expiry after week rounding using getStakedAmountAndExpiry
        (, uint256 aliceLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Move forward by some period and record timestamp
        vm.warp(t0 + MAX_STAKE_TIME_S / 6);
        uint256 t1 = block.timestamp;
        
        // Move forward by some bigger period and record timestamp
        vm.warp(t0 + MAX_STAKE_TIME_S / 6 * 2);
        uint256 t2 = block.timestamp;
        
        // Bob stakes at t2 for half max time
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        
        vm.warp(t0 + MAX_STAKE_TIME_S / 6 * 3);
        
        // Initial voting power should be _approximately_ AMOUNT,
        // with small precision loss from slope calculation that is used to construct bias.
        uint256 alicePowerAtT0 = veToken.getPastVotes(alice, t0);
        assertApproxEqRel(alicePowerAtT0, AMOUNT, 0.01e18);
        assertEq(alicePowerAtT0, _calculateExpectedVotePower(AMOUNT, t0, aliceLockEnd));

        uint256 alicePowerAtT1 = veToken.getPastVotes(alice, t1);
        assertEq(alicePowerAtT1, _calculateExpectedVotePower(AMOUNT, t1, aliceLockEnd));
        
        uint256 alicePowerAtT2 = veToken.getPastVotes(alice, t2);
        assertEq(alicePowerAtT2, _calculateExpectedVotePower(AMOUNT, t2, aliceLockEnd));
        
        // Bob should have 0 power at t1 (before staking)
        uint256 bobPowerAtT1 = veToken.getPastVotes(bob, t1);
        assertEq(bobPowerAtT1, 0);
    }
    
    function testGetTotalVotesWithDecay() public {
        // Alice stakes for max time
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S); // Max time
        (, uint256 aliceLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        uint256 totalAfterAlice = veToken.getPastTotalSupply(block.timestamp);
        assertApproxEqRel(totalAfterAlice, AMOUNT, 0.01e18, "Total after Alice incorrect");
        
        // 10 weeks later Bob stakes for half max time
        vm.warp(block.timestamp + 10 weeks);
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2); // Half max time
        (, uint256 bobLockEnd) = veToken.getStakedAmountAndExpiry(bob);
        
        // At this point, total should be Alice's decayed + Bob's initial
        uint256 aliceDecayed = _calculateExpectedVotePower(AMOUNT, block.timestamp, aliceLockEnd);
        uint256 bobInitial = _calculateExpectedVotePower(AMOUNT, block.timestamp, bobLockEnd);
        uint256 expectedTotal = aliceDecayed + bobInitial;
        uint256 totalAfterBob = veToken.getPastTotalSupply(block.timestamp);
        assertApproxEqRel(totalAfterBob, expectedTotal, 0.01e18, "Total after Bob incorrect");
        
        // Fast forward to when Bob's lock expires
        vm.warp(bobLockEnd);
        
        // Only Alice's power should remain
        uint256 aliceExpectedPower = _calculateExpectedVotePower(AMOUNT, block.timestamp, aliceLockEnd);
        uint256 totalAtBobExpiry = veToken.getPastTotalSupply(block.timestamp);
        assertApproxEqRel(totalAtBobExpiry, aliceExpectedPower, 0.01e18, "Total at Bob expiry incorrect");
    }
    
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
        
        // Slope changes should be negative (following Velodrome pattern)
        assertTrue(aliceSlopeChange < 0, "Alice slope change should be negative");
        assertTrue(bobSlopeChange < 0, "Bob slope change should be negative");
        
        // Move to just before Alice expiry
        vm.warp(aliceExpiry - 1);
        uint256 totalBeforeExpiry = veToken.getPastTotalSupply(block.timestamp);
        
        // Move past Alice expiry
        vm.warp(aliceExpiry + 1);
        uint256 totalAfterExpiry = veToken.getPastTotalSupply(block.timestamp);
        
        // Total should decrease after expiry (Bob's power only)
        assertTrue(totalAfterExpiry < totalBeforeExpiry, "Total should decrease after expiry");
    }
    
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
        uint256 expectedPower = _calculateExpectedVotePower(AMOUNT * 2, block.timestamp, lockEnd);
        assertApproxEqRel(afterAddPower, expectedPower, 0.01e18, "Power after add incorrect");
    }
    
    function testLockExtensionUpdatesVotingPower() public {
        // Alice stakes for minimum duration
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, 0);
        (, uint256 initialLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        uint256 initialPower = veToken.getVotes(alice);
        uint256 expectedInitial = _calculateExpectedVotePower(AMOUNT, block.timestamp, initialLockEnd);
        assertApproxEqRel(initialPower, expectedInitial, 0.01e18, "Initial power incorrect");
        int128 initialScheduledSlope = veToken.slopeChanges(initialLockEnd);
        assertTrue(initialScheduledSlope < 0, "Slope change should be scheduled when lock ends");
        
        // Extend lock to max time
        vm.prank(alice);
        veToken.extendLockToTime(tokenId, type(uint256).max);
        (, uint256 extendedLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        assertGt(extendedLockEnd, initialLockEnd, "Lock end should be extended");
        
        uint256 extendedPower = veToken.getVotes(alice);
        uint256 expectedExtended = _calculateExpectedVotePower(AMOUNT, block.timestamp, extendedLockEnd);
        assertApproxEqRel(extendedPower, expectedExtended, 0.01e18, "Extended power incorrect");
        assertGt(extendedPower, initialPower, "Extended power should be greater than initial power");
        
        // Check slope change is updated
        int128 finalSlopeChange = veToken.slopeChanges(extendedLockEnd);
        assertTrue(finalSlopeChange < 0, "Extended slope change should be scheduled");
        int128 initialScheduledSlope2 = veToken.slopeChanges(initialLockEnd);
        assertEq(0, initialScheduledSlope2, "Initialially scheduled slope change should have been removed");
    }
    
    
    function testVotesNeverNegative() public {
        // Stake and let it expire
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 5 weeks);
        
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Move well past expiry
        vm.warp(lockEnd + 10 weeks);
        
        uint256 expiredVotes = veToken.getVotes(alice);
        assertEq(expiredVotes, 0, "Expired votes should be 0, not negative");
        
        uint256 totalVotes = veToken.getPastTotalSupply(block.timestamp);
        assertEq(totalVotes, 0, "Total votes should be 0 when all expired");
    }
    
    function testVotingPowerWithDifferentLockDurations() public {
        // Alice stakes for max time
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S);
        
        // Bob stakes for half max time
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 2);
        
        // Charlie stakes for quarter max time
        vm.prank(charlie);
        veToken.stake(AMOUNT, block.timestamp + MAX_STAKE_TIME_S / 4);
        
        // Get actual lock ends
        (, uint256 aliceEnd) = veToken.getStakedAmountAndExpiry(alice);
        (, uint256 bobEnd) = veToken.getStakedAmountAndExpiry(bob);
        (, uint256 charlieEnd) = veToken.getStakedAmountAndExpiry(charlie);
        
        uint256 alicePower = veToken.getVotes(alice);
        uint256 bobPower = veToken.getVotes(bob);
        uint256 charliePower = veToken.getVotes(charlie);
        assertGt(alicePower, bobPower, "Alice should have more power than Bob");
        assertGt(bobPower, charliePower, "Bob should have more power than Charlie");
        
        // Calculate expected powers
        uint256 expectedAlice = _calculateExpectedVotePower(AMOUNT, block.timestamp, aliceEnd);
        uint256 expectedBob = _calculateExpectedVotePower(AMOUNT, block.timestamp, bobEnd);
        uint256 expectedCharlie = _calculateExpectedVotePower(AMOUNT, block.timestamp, charlieEnd);
        
        assertApproxEqRel(alicePower, expectedAlice, 0.01e18, "Alice power incorrect");
        assertApproxEqRel(bobPower, expectedBob, 0.01e18, "Bob power incorrect");
        assertApproxEqRel(charliePower, expectedCharlie, 0.01e18, "Charlie power incorrect");
    }
}