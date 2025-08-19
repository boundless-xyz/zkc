// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../veZKC.t.sol";
import "../../src/interfaces/IStaking.sol";

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
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        
        // Get actual expiry time using getStakedAmountAndExpiry
        (uint256 stakedAmount, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(stakedAmount, AMOUNT);
        
        // Initial voting power should match veZKC calculation
        uint256 initialPower = veToken.getVotes(alice);
        assertEq(initialPower, _calculateExpectedVotePower(AMOUNT, vm.getBlockTimestamp(), lockEnd));
        
        // After 50% of stake time
        vm.warp(vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 4);
        uint256 halfTimePower = veToken.getVotes(alice);
        assertEq(halfTimePower, _calculateExpectedVotePower(AMOUNT, vm.getBlockTimestamp(), lockEnd));
        
        // After lock expires, power should be 0
        vm.warp(lockEnd);
        uint256 expiredPower = veToken.getVotes(alice);
        assertEq(expiredPower, 0);
    }
    
    function testGetPastVotesHistoricalAccuracy() public {
        // Record initial timestamp
        uint256 t0 = vm.getBlockTimestamp();
        
        // Alice stakes at t0 for max time
        vm.prank(alice);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S);
        
        // Get actual expiry after week rounding using getStakedAmountAndExpiry
        (, uint256 aliceLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Move forward by some period and record timestamp
        vm.warp(t0 + MAX_STAKE_TIME_S / 6);
        uint256 t1 = vm.getBlockTimestamp();
        
        // Move forward by some bigger period and record timestamp
        vm.warp(t0 + MAX_STAKE_TIME_S / 6 * 2);
        uint256 t2 = vm.getBlockTimestamp();
        
        // Bob stakes at t2 for half max time
        vm.prank(bob);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        
        vm.warp(t0 + MAX_STAKE_TIME_S / 6 * 3);
        
        // Initial voting power should be _approximately_ AMOUNT,
        // with small precision loss from slope calculation that is used to construct bias.
        // Note: t0 is now in the past since we've warped forward

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
        // Store timestamps for historical queries
        uint256 t0 = vm.getBlockTimestamp();
        
        // Alice stakes for max time
        vm.prank(alice);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S); // Max time
        (, uint256 aliceLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        uint256 t1 = vm.getBlockTimestamp(); // After Alice stakes
        
        // 10 weeks later Bob stakes for half max time
        vm.warp(vm.getBlockTimestamp() + 10 weeks);
        vm.prank(bob);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2); // Half max time
        (, uint256 bobLockEnd) = veToken.getStakedAmountAndExpiry(bob);
        
        uint256 t2 = vm.getBlockTimestamp(); // After Bob stakes
        
        // Fast forward to when Bob's lock expires
        vm.warp(bobLockEnd);
        uint256 t3 = vm.getBlockTimestamp(); // At Bob expiry
        
        // Warp to end to do historical assertions
        vm.warp(vm.getBlockTimestamp() + 1 weeks);
        
        // Historical assertions
        uint256 totalAfterAlice = veToken.getPastTotalSupply(t1);
        assertApproxEqRel(totalAfterAlice, AMOUNT, 0.01e18, "Total after Alice incorrect");
        
        // At t2, total should be Alice's decayed + Bob's initial
        uint256 aliceDecayed = _calculateExpectedVotePower(AMOUNT, t2, aliceLockEnd);
        uint256 bobInitial = _calculateExpectedVotePower(AMOUNT, t2, bobLockEnd);
        uint256 expectedTotal = aliceDecayed + bobInitial;
        uint256 totalAfterBob = veToken.getPastTotalSupply(t2);
        assertApproxEqRel(totalAfterBob, expectedTotal, 0.01e18, "Total after Bob incorrect");
        
        // At Bob expiry, only Alice's power should remain
        uint256 aliceExpectedPower = _calculateExpectedVotePower(AMOUNT, t3, aliceLockEnd);
        uint256 totalAtBobExpiry = veToken.getPastTotalSupply(t3);
        assertApproxEqRel(totalAtBobExpiry, aliceExpectedPower, 0.01e18, "Total at Bob expiry incorrect");
    }
    
    function testSlopeChangesAtExpiry() public {
        // Alice stakes for 8 weeks
        vm.prank(alice);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + 8 weeks);
        
        (, uint256 aliceExpiry) = veToken.getStakedAmountAndExpiry(alice);
        
        // Bob stakes for 12 weeks  
        vm.prank(bob);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + 12 weeks);
        
        (, uint256 bobExpiry) = veToken.getStakedAmountAndExpiry(bob);
        
        // Check slope changes are scheduled
        int128 aliceSlopeChange = veToken.slopeChanges(aliceExpiry);
        int128 bobSlopeChange = veToken.slopeChanges(bobExpiry);
        
        // Slope changes should be negative (following Velodrome pattern)
        assertTrue(aliceSlopeChange < 0, "Alice slope change should be negative");
        assertTrue(bobSlopeChange < 0, "Bob slope change should be negative");
        
        // Store timestamps for historical queries
        vm.warp(aliceExpiry - 1);
        uint256 t0 = vm.getBlockTimestamp(); // Just before Alice expiry
        
        vm.warp(aliceExpiry + 1);
        uint256 t1 = vm.getBlockTimestamp(); // Just after Alice expiry
        
        // Warp to end to do historical assertions
        vm.warp(vm.getBlockTimestamp() + 1 weeks);
        
        // Historical assertions
        uint256 totalBeforeExpiry = veToken.getPastTotalSupply(t0);
        uint256 totalAfterExpiry = veToken.getPastTotalSupply(t1);
        
        // Total should decrease after expiry (Bob's power only)
        assertTrue(totalAfterExpiry < totalBeforeExpiry, "Total should decrease after expiry");
    }
    
    function testAddToStakeUpdatesVotingPower() public {
        // Alice stakes initially
        vm.prank(alice);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + 52 weeks);
        
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        uint256 initialPower = veToken.getVotes(alice);
        
        // Move forward 10 weeks
        vm.warp(vm.getBlockTimestamp() + 10 weeks);
        
        uint256 decayedPower = veToken.getVotes(alice);
        assertLt(decayedPower, initialPower, "Power should decay over time");
        
        // Add more stake
        vm.prank(alice);
        veToken.addToStake(AMOUNT);
        
        // Get updated amount after adding stake
        (uint256 updatedAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(updatedAmount, AMOUNT * 2, "Amount should be doubled");
        
        // Power should increase but still be based on remaining time
        uint256 afterAddPower = veToken.getVotes(alice);
        uint256 expectedPower = _calculateExpectedVotePower(AMOUNT * 2, vm.getBlockTimestamp(), lockEnd);
        assertApproxEqRel(afterAddPower, expectedPower, 0.01e18, "Power after add incorrect");
    }
    
    function testLockExtensionUpdatesVotingPower() public {
        // Alice stakes for minimum duration
        vm.prank(alice);
        veToken.stake(AMOUNT, 0);
        (, uint256 initialLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        uint256 initialPower = veToken.getVotes(alice);
        uint256 expectedInitial = _calculateExpectedVotePower(AMOUNT, vm.getBlockTimestamp(), initialLockEnd);
        assertApproxEqRel(initialPower, expectedInitial, 0.01e18, "Initial power incorrect");
        int128 initialScheduledSlope = veToken.slopeChanges(initialLockEnd);
        assertTrue(initialScheduledSlope < 0, "Slope change should be scheduled when lock ends");
        
        // Extend lock to max time
        vm.prank(alice);
        veToken.extendStakeLockup(type(uint256).max);
        (, uint256 extendedLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        assertGt(extendedLockEnd, initialLockEnd, "Lock end should be extended");
        
        uint256 extendedPower = veToken.getVotes(alice);
        uint256 expectedExtended = _calculateExpectedVotePower(AMOUNT, vm.getBlockTimestamp(), extendedLockEnd);
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
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + 5 weeks);
        
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Move well past expiry and store timestamp
        vm.warp(lockEnd + 10 weeks);
        uint256 t0 = vm.getBlockTimestamp(); // Well past expiry
        
        // Warp to end to do historical assertions
        vm.warp(vm.getBlockTimestamp() + 1 weeks);
        
        // Current votes should be 0 (not negative)
        uint256 expiredVotes = veToken.getVotes(alice);
        assertEq(expiredVotes, 0, "Expired votes should be 0, not negative");
        
        // Historical assertion
        uint256 totalVotes = veToken.getPastTotalSupply(t0);
        assertEq(totalVotes, 0, "Total votes should be 0 when all expired");
    }
    
    function testVotingPowerWithDifferentLockDurations() public {
        // Alice stakes for max time
        vm.prank(alice);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S);
        
        // Bob stakes for half max time
        vm.prank(bob);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        
        // Charlie stakes for quarter max time
        vm.prank(charlie);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 4);
        
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
        uint256 expectedAlice = _calculateExpectedVotePower(AMOUNT, vm.getBlockTimestamp(), aliceEnd);
        uint256 expectedBob = _calculateExpectedVotePower(AMOUNT, vm.getBlockTimestamp(), bobEnd);
        uint256 expectedCharlie = _calculateExpectedVotePower(AMOUNT, vm.getBlockTimestamp(), charlieEnd);
        
        assertApproxEqRel(alicePower, expectedAlice, 0.01e18, "Alice power incorrect");
        assertApproxEqRel(bobPower, expectedBob, 0.01e18, "Bob power incorrect");
        assertApproxEqRel(charliePower, expectedCharlie, 0.01e18, "Charlie power incorrect");
    }

    // Test extending expired lock restores voting power
    function testExtendExpiredLockRestoresVotingPower() public {
        // Stake with minimum duration
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT, 0);
        vm.stopPrank();
        
        // Get lock end and initial voting power
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        uint256 initialVotingPower = veToken.getVotes(alice);
        assertGt(initialVotingPower, 0, "Should have voting power initially");
        
        // Let it expire
        vm.warp(lockEnd + 1);
        assertEq(veToken.getVotes(alice), 0, "Voting power should be 0 after expiry");
        
        // Extend the expired lock
        uint256 newLockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2;
        vm.prank(alice);
        veToken.extendStakeLockup(newLockEnd);
        
        // Verify voting power is restored
        uint256 restoredVotingPower = veToken.getVotes(alice);
        assertGt(restoredVotingPower, 0, "Voting power should be restored after extension");
        
        // Check reward power is also restored
        uint256 rewardPower = veToken.getRewards(alice);
        assertEq(rewardPower, AMOUNT, "Reward power should equal staked amount");
    }

    // Test adding to expired lock doesn't restore voting power
    function testCannotAddToExpiredLock() public {
        uint256 ADD_AMOUNT = 5_000 * 10**18;
        
        // Stake with minimum duration
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT + ADD_AMOUNT);
        veToken.stake(AMOUNT, 0);
        vm.stopPrank();
        
        // Get lock end
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Let it expire
        vm.warp(lockEnd + 1);
        assertEq(veToken.getVotes(alice), 0, "Voting power should be 0 after expiry");
        
        // Try to add to expired stake (should fail)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IStaking.CannotAddToExpiredPosition.selector));
        veToken.addToStake(ADD_AMOUNT);
        
        // Verify amounts haven't changed
        (uint256 newAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(newAmount, AMOUNT, "Amount should not change after failed add");
        assertEq(veToken.getVotes(alice), 0, "Voting power should remain 0");
        
        // Reward power should also not change since add failed
        uint256 rewardPower = veToken.getRewards(alice);
        assertEq(rewardPower, AMOUNT, "Reward power should not change after failed add");
    }

    // Test complex flow: stake -> expire -> add -> extend to verify slope changes
    function testExpiredAddExtendSlopeChanges() public {
        uint256 ADD_AMOUNT = 5_000 * 10**18;
        
        // 1. Alice stakes with minimum duration
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT + ADD_AMOUNT);
        uint256 tokenId = veToken.stake(AMOUNT, 0);
        vm.stopPrank();
        
        // Get initial lock end and voting power
        (, uint256 initialLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        uint256 initialVotingPower = veToken.getVotes(alice);
        assertGt(initialVotingPower, 0, "Should have initial voting power");
        
        // Check initial slope change is scheduled
        int128 initialSlopeChange = veToken.slopeChanges(initialLockEnd);
        assertTrue(initialSlopeChange < 0, "Initial slope change should be negative");
        
        // 2. Bob also stakes to have a reference point
        vm.startPrank(bob);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        uint256 t0 = vm.getBlockTimestamp(); // After both stakes
        
        // 3. Let Alice's lock expire
        vm.warp(initialLockEnd + 1);
        
        // Verify Alice has 0 voting power but Bob still has power
        assertEq(veToken.getVotes(alice), 0, "Alice should have 0 voting power after expiry");
        assertGt(veToken.getVotes(bob), 0, "Bob should still have voting power");
        
        // Check slope change is still there (it already executed)
        assertEq(veToken.slopeChanges(initialLockEnd), initialSlopeChange, "Slope change should remain");
        
        // 4. Alice tries to add to expired stake (should fail)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IStaking.CannotAddToExpiredPosition.selector));
        veToken.addToStake(ADD_AMOUNT);
    
        // 5. Alice extends the expired lock first
        uint256 newLockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 4;
        vm.prank(alice);
        veToken.extendStakeLockup(newLockEnd);
        
        // Get actual new lock end after week rounding
        (, uint256 actualNewLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // 6. Now Alice can add to the re-activated position
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);
        
        // Verify amounts updated
        (uint256 amountAfterAdd,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(amountAfterAdd, AMOUNT + ADD_AMOUNT, "Amount should be updated after extension");
        
        // 7. Verify voting power reflects the FULL amount by calculating it
        uint256 restoredVotingPower = veToken.getVotes(alice);
        assertGt(restoredVotingPower, 0, "Voting power should be restored");
        uint256 expectedVotingPower = _calculateExpectedVotePower(AMOUNT + ADD_AMOUNT, vm.getBlockTimestamp(), actualNewLockEnd);
        assertApproxEqRel(restoredVotingPower, expectedVotingPower, 0.01e18, "Voting power should reflect full amount after add");
        
        // 8. Check new slope change is scheduled correctly
        // The new slope should be based on the FULL amount (AMOUNT + ADD_AMOUNT)
        int128 newSlopeChange = veToken.slopeChanges(actualNewLockEnd);
        assertTrue(newSlopeChange < 0, "New slope change should be scheduled");
        int128 expectedSlope = -int128(int256(AMOUNT + ADD_AMOUNT)) / int128(int256(MAX_STAKE_TIME_S));
        assertEq(newSlopeChange, expectedSlope, "New slope change should match full amount");
        
        uint256 t1 = vm.getBlockTimestamp(); // After Alice's extension and add
        
        // 9. Fast forward to new lock end and verify slope change executes correctly
        vm.warp(actualNewLockEnd + 1);
        uint256 t2 = vm.getBlockTimestamp(); // After Alice's new lock expires
        
        // Warp to end to do historical assertions
        vm.warp(vm.getBlockTimestamp() + 1 weeks);
        
        // Historical assertions
        uint256 totalSupplyBeforeExpiry = veToken.getPastTotalSupply(t0);
        assertGt(totalSupplyBeforeExpiry, 0, "Total supply should include both stakes");
        
        uint256 totalSupplyAfterExtend = veToken.getPastTotalSupply(t1);
        uint256 bobPowerAtT1 = veToken.getPastVotes(bob, t1);
        assertGt(totalSupplyAfterExtend, bobPowerAtT1, "Total should be more than just Bob's power");
        
        // At t2, total should be Bob's power
        uint256 finalTotalSupply = veToken.getPastTotalSupply(t2);
        uint256 bobPowerAtT2 = veToken.getPastVotes(bob, t2);
        assertApproxEqRel(finalTotalSupply, bobPowerAtT2, 0.01e18, "Total should equal Bob's remaining power");
        
        // Alice should have 0 voting power after her new lock expires
        assertEq(veToken.getVotes(alice), 0, "Alice voting power should be 0 after new lock expires");
        assertEq(veToken.getPastVotes(alice, t2), 0, "Alice voting power should be 0 after new lock expires");
    }
    
    function testVotesTimepointValidation() public {
        // Alice stakes first
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        uint256 currentTime = vm.getBlockTimestamp();
        
        // Test that calling getPastVotes with current timestamp reverts
        vm.expectRevert();
        veToken.getPastVotes(alice, currentTime);
        
        // Test that calling getPastTotalSupply with current timestamp reverts
        vm.expectRevert();
        veToken.getPastTotalSupply(currentTime);
        
        // Test that calling with future timestamp reverts
        vm.expectRevert();
        veToken.getPastVotes(alice, currentTime + 1);
        
        vm.expectRevert();
        veToken.getPastTotalSupply(currentTime + 1);
        
        // Test that calling with past timestamp works
        vm.warp(currentTime + 1000);
        
        uint256 pastVotes = veToken.getPastVotes(alice, currentTime);
        uint256 pastTotalSupply = veToken.getPastTotalSupply(currentTime);
        
        // Voting power should be roughly half the staked amount (since we locked for half max time)
        assertApproxEqRel(pastVotes, AMOUNT / 2, 0.01e18, "Past votes should be roughly half of staked amount");
        assertApproxEqRel(pastTotalSupply, AMOUNT / 2, 0.01e18, "Past total supply should be roughly half of staked amount");
    }

    function testMultipleVotingActionsInSameBlock() public {
        uint256 ADD_AMOUNT = 5_000 * 10**18;
        
        // Alice stakes initially
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT + ADD_AMOUNT);
        veToken.stake(AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        // Get lock end for calculations
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Store current timestamp - all actions will happen in this block
        uint256 actionTimestamp = vm.getBlockTimestamp();
        
        // Verify initial state
        uint256 votesAfterStake = veToken.getVotes(alice);
        uint256 expectedAfterStake = _calculateExpectedVotePower(AMOUNT, actionTimestamp, lockEnd);
        assertApproxEqRel(votesAfterStake, expectedAfterStake, 0.01e18, "Votes after initial stake");
        
        // Perform second action in same block: add to stake
        // Note: We don't warp time, so this happens in the same block
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);
        
        // Verify final state after both actions
        uint256 votesAfterAdd = veToken.getVotes(alice);
        uint256 expectedAfterAdd = _calculateExpectedVotePower(AMOUNT + ADD_AMOUNT, actionTimestamp, lockEnd);
        assertApproxEqRel(votesAfterAdd, expectedAfterAdd, 0.01e18, "Votes after adding to stake");
        
        // The key test: move to next block and query historical votes for the action block
        vm.warp(actionTimestamp + 1);
        
        // When querying votes for the block where both actions happened,
        // binary search should return the FINAL state (after both stake and addToStake)
        uint256 historicalVotes = veToken.getPastVotes(alice, actionTimestamp);
        assertApproxEqRel(historicalVotes, expectedAfterAdd, 0.01e18, 
            "Historical votes should reflect final state after all actions in the block");
        
        // Should NOT equal the intermediate state after just the initial stake
        assertTrue(historicalVotes != expectedAfterStake || expectedAfterStake == expectedAfterAdd, 
            "Historical votes should not return intermediate state unless both are equal");
        
        // Verify total supply also reflects final state
        uint256 historicalTotalSupply = veToken.getPastTotalSupply(actionTimestamp);
        assertApproxEqRel(historicalTotalSupply, expectedAfterAdd, 0.01e18,
            "Historical total supply should reflect final state");
    }
}