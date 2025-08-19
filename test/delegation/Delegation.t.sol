// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../veZKC.t.sol";

contract DelegationTest is veZKCTest {
    address treasury = makeAddr("treasury");
    
    uint256 constant STAKE_AMOUNT = 1000e18;
    uint256 constant LOCK_DURATION = 52 weeks; // 1 year

    function setUp() public override {
        super.setUp();
        
        vm.startPrank(admin);
        zkc.grantRole(zkc.MINTER_ROLE(), admin);
        
        // Mint tokens to test accounts
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = STAKE_AMOUNT * 3;
        amounts[1] = STAKE_AMOUNT * 3;
        amounts[2] = STAKE_AMOUNT * 3;
        
        zkc.initialMint(recipients, amounts);
        vm.stopPrank();
        
        vm.prank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT * 3);
        
        vm.prank(bob);
        zkc.approve(address(veToken), STAKE_AMOUNT * 3);
        
        vm.prank(charlie);
        zkc.approve(address(veToken), STAKE_AMOUNT * 3);
    }

    function testVotingDelegationWithDecay() public {
        uint256 lockEnd = vm.getBlockTimestamp() + LOCK_DURATION;
        
        // Both Alice and Bob stake with same lock end time
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT * 2, lockEnd);
        
        vm.prank(bob);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Record initial voting power
        uint256 aliceInitialVotes = veToken.getVotes(alice);
        uint256 bobInitialVotes = veToken.getVotes(bob);
        console.log("aliceInitialVotes", aliceInitialVotes);
        console.log("bobInitialVotes", bobInitialVotes);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        // Check voting power immediately after delegation
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power after delegation");
        uint256 bobDelegatedVotes = veToken.getVotes(bob);
        assertApproxEqAbs(bobDelegatedVotes, aliceInitialVotes + bobInitialVotes, 5e7, "Bob should have combined voting power");
        
        // Move forward in time and test decay
        vm.warp(vm.getBlockTimestamp() + LOCK_DURATION / 4);
        assertLt(veToken.getVotes(bob), bobDelegatedVotes, "Bob's delegated voting power should decay");
        
        vm.warp(lockEnd + 1);
        assertEq(veToken.getVotes(bob), 0, "All voting power should be zero after lock expiry");
    }

    function testDelegateeExtendsLockAffectsDelegator() public {
        uint256 lockEnd = vm.getBlockTimestamp() + LOCK_DURATION;
        
        // Both Alice and Bob stake with same lock end time
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        vm.prank(bob);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        uint256 bobVotesAfterDelegation = veToken.getVotes(bob);
        
        // Bob extends his lock - this should affect Alice's lock too since she's delegated
        uint256 newLockEnd = lockEnd + 26 weeks; // Add 6 months
        vm.prank(bob);
        veToken.extendStakeLockup(newLockEnd);
        
        // Bob's voting power should increase due to longer lock duration
        uint256 bobVotesAfterExtension = veToken.getVotes(bob);
        assertGt(bobVotesAfterExtension, bobVotesAfterDelegation, "Bob's voting power should increase when he extends lock");
        
        // Move to original lock end time - both should still have power since Bob extended
        vm.warp(lockEnd + 1);
        assertGt(veToken.getVotes(bob), 0, "Bob should still have voting power after original lock end");
        
        // Alice undelegates and should inherit Bob's extended lock time
        vm.prank(alice);
        veToken.delegate(address(0));
        
        // Alice should now have voting power until the new lock end time
        assertGt(veToken.getVotes(alice), 0, "Alice should have voting power with extended lock end");
        
        // Move to new lock end time
        vm.warp(newLockEnd + 1);
        assertEq(veToken.getVotes(alice), 0, "Alice should have no power after extended lock expires");
    }

    function testDelegatorCannotExtendLockWhileDelegated() public {
        uint256 lockEnd = vm.getBlockTimestamp() + LOCK_DURATION;
        
        // Both Alice and Bob stake with same lock end time
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        vm.prank(bob);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        // Alice tries to extend her lock - this should fail since she's delegated
        uint256 newLockEnd = lockEnd + 26 weeks;
        vm.prank(alice);
        vm.expectRevert(); // Should revert because Alice has delegated
        veToken.extendStakeLockup(newLockEnd);
    }

    function testDelegatorCanExtendAfterUndelegating() public {
        uint256 lockEnd = vm.getBlockTimestamp() + LOCK_DURATION;
        
        // Both Alice and Bob stake with same lock end time
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        vm.prank(bob);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        // Bob extends his lock
        uint256 bobExtendedLockEnd = lockEnd + 26 weeks;
        vm.prank(bob);
        veToken.extendStakeLockup(bobExtendedLockEnd);
        
        // Alice undelegates
        vm.prank(alice);
        veToken.delegate(address(0));
        
        // Alice should now be able to extend her lock (she inherited Bob's lock end time)
        uint256 aliceNewLockEnd = bobExtendedLockEnd + 13 weeks;
        vm.prank(alice);
        veToken.extendStakeLockup(aliceNewLockEnd); // Should work now
        
        // Verify Alice's lock was extended
        vm.warp(bobExtendedLockEnd + 1);
        assertGt(veToken.getVotes(alice), 0, "Alice should still have voting power after Bob's extended lock end");
        
        vm.warp(aliceNewLockEnd + 1);
        assertEq(veToken.getVotes(alice), 0, "Alice should have no power after her own extended lock end");
    }

    function testDelegatorCanAddToStakeWhileDelegated() public {
        uint256 lockEnd = vm.getBlockTimestamp() + LOCK_DURATION;
        
        // Both Alice and Bob stake with same lock end time
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        vm.prank(bob);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        uint256 bobVotesAfterDelegation = veToken.getVotes(bob);
        
        // Alice should be able to add to her stake even while delegated
        vm.prank(alice);
        veToken.addToStake(STAKE_AMOUNT);
        
        // Bob's voting power should increase due to Alice's increased stake
        uint256 bobVotesAfterStakeIncrease = veToken.getVotes(bob);
        assertGt(bobVotesAfterStakeIncrease, bobVotesAfterDelegation, "Bob's voting power should increase when Alice adds to stake");
    }

    function testRewardDelegationWithStakeChanges() public {
        uint256 lockEnd = vm.getBlockTimestamp() + LOCK_DURATION;
        
        // Alice stakes
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Alice delegates rewards to treasury
        vm.prank(alice);
        veToken.delegateRewards(treasury);
        
        assertEq(veToken.getRewards(treasury), STAKE_AMOUNT);
        
        // Alice adds more stake - treasury's reward power should increase
        vm.prank(alice);
        veToken.addToStake(STAKE_AMOUNT);
        
        assertEq(veToken.getRewards(treasury), STAKE_AMOUNT * 2, "Treasury's reward power should increase with Alice's stake");
        
        // Time doesn't affect reward power
        vm.warp(vm.getBlockTimestamp() + LOCK_DURATION / 2);
        assertEq(veToken.getRewards(treasury), STAKE_AMOUNT * 2, "Treasury's reward power should not decay");
        
        // Even after lock expiry
        vm.warp(lockEnd + 1);
        assertEq(veToken.getRewards(treasury), STAKE_AMOUNT * 2, "Treasury should keep reward power after lock expiry");
    }

    function testMultipleDelegationChanges() public {
        uint256 lockEnd = vm.getBlockTimestamp() + LOCK_DURATION;
        
        // Alice, Bob, and Charlie all stake with same lock end time
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        vm.prank(bob);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        vm.prank(charlie);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        uint256 aliceVotes = veToken.getVotes(alice);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        assertEq(veToken.getVotes(bob), aliceVotes * 2, "Bob should have Alice's + his own votes");
        
        // Bob extends his lock - affects Alice too
        uint256 newLockEnd = lockEnd + 26 weeks;
        vm.prank(bob);
        veToken.extendStakeLockup(newLockEnd);
        
        uint256 bobExtendedVotes = veToken.getVotes(bob);
        assertGt(bobExtendedVotes, aliceVotes * 2, "Bob's votes should increase after extension");
        
        // Alice redelegates to Charlie
        vm.prank(alice);
        vm.expectRevert("Lock end times must match"); // Charlie still has original lock end
        veToken.delegate(charlie);
        
        // Charlie needs to extend his lock to match Bob's
        vm.prank(charlie);
        veToken.extendStakeLockup(newLockEnd);
        
        // Now Alice can delegate to Charlie
        vm.prank(alice);
        veToken.delegate(charlie);
        
        // Verify power redistribution
        // Bob now has only his own (extended) voting power, which should be >= original
        assertGt(veToken.getVotes(bob), aliceVotes, "Bob should retain only his (extended) votes");
        assertGt(veToken.getVotes(charlie), aliceVotes, "Charlie should have Alice's delegated votes");
    }

    function testVotingDelegationRequiresMatchingLockTimes() public {
        // Alice stakes for 1 year
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT, vm.getBlockTimestamp() + 52 weeks);
        
        // Bob stakes for 2 years
        vm.prank(bob);
        veToken.stake(STAKE_AMOUNT, vm.getBlockTimestamp() + 104 weeks);
        
        // Alice tries to delegate to Bob (should fail due to mismatched lock times)
        vm.prank(alice);
        vm.expectRevert("Lock end times must match");
        veToken.delegate(bob);
    }

    function testRewardDelegationIndependentOfLockTimes() public {
        // Alice stakes for 1 year
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT, vm.getBlockTimestamp() + 52 weeks);
        
        // Bob stakes for 2 years
        vm.prank(bob);
        veToken.stake(STAKE_AMOUNT, vm.getBlockTimestamp() + 104 weeks);
        
        // Alice can delegate rewards to Bob regardless of lock times
        vm.prank(alice);
        veToken.delegateRewards(bob);
        
        assertEq(veToken.getRewards(bob), STAKE_AMOUNT * 2, "Bob should have both his and Alice's reward power");
        
        // Alice can also delegate rewards to treasury (no position)
        vm.prank(alice);
        veToken.delegateRewards(treasury);
        
        assertEq(veToken.getRewards(treasury), STAKE_AMOUNT, "Treasury should have Alice's reward power");
        assertEq(veToken.getRewards(bob), STAKE_AMOUNT, "Bob should only have his own reward power");
    }

    function testCombinedVotingAndRewardDelegationScenario() public {
        uint256 lockEnd = vm.getBlockTimestamp() + LOCK_DURATION;
        
        // Alice and Bob stake with same lock end
        vm.prank(alice);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        vm.prank(bob);
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Alice delegates voting to Bob and rewards to treasury
        vm.prank(alice);
        veToken.delegate(bob);
        
        vm.prank(alice);
        veToken.delegateRewards(treasury);
        
        // Bob extends his lock - this affects Alice's voting but not rewards
        uint256 newLockEnd = lockEnd + 26 weeks;
        vm.prank(bob);
        veToken.extendStakeLockup(newLockEnd);
        
        // Check that voting power increased but reward power stayed the same
        uint256 bobVotingPower = veToken.getVotes(bob);
        uint256 treasuryRewardPower = veToken.getRewards(treasury);
        
        assertGt(bobVotingPower, 0, "Bob should have extended voting power");
        assertEq(treasuryRewardPower, STAKE_AMOUNT, "Treasury reward power should be unchanged");
        
        // Move past original lock end - voting power should still exist, rewards unchanged
        vm.warp(lockEnd + 1);
        
        assertGt(veToken.getVotes(bob), 0, "Bob should still have voting power after original lock end");
        assertEq(veToken.getRewards(treasury), STAKE_AMOUNT, "Treasury should keep reward power");
        
        // Alice undelegates voting - inherits Bob's extended lock time
        vm.prank(alice);
        veToken.delegate(address(0));
        
        assertGt(veToken.getVotes(alice), 0, "Alice should have voting power with extended lock time");
        assertEq(veToken.getRewards(treasury), STAKE_AMOUNT, "Treasury should still have reward power");
    }
}