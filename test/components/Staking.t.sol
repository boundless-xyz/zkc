// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../veZKC.t.sol";
import "../../src/interfaces/IStaking.sol";

contract veZKCStakeTest is veZKCTest {
    uint256 constant STAKE_AMOUNT = 10_000 * 10**18;
    uint256 constant ADD_AMOUNT = 5_000 * 10**18;
    
    uint256 alicePrivateKey = 0xA11CE;
    uint256 bobPrivateKey = 0xB0B;
    
    function setUp() public override {
        super.setUp();
        
        // Set up alice and bob with known private keys for permit testing
        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);
        
        // Fund test accounts with extra tokens for permit tests
        vm.startPrank(admin);
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = AMOUNT * 10;
        amounts[1] = AMOUNT * 10;
        amounts[2] = AMOUNT * 10;
        
        zkc.initialMint(recipients, amounts);
        vm.stopPrank();
    }

    // Test basic staking with approval
    function testStakeWithApproval() public {
        uint256 lockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2; // Half max time
        
        vm.startPrank(alice);
        
        // First try staking without approval (should fail)
        vm.expectRevert();
        veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Now approve and stake (should succeed)
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 tokenId = veToken.stake(STAKE_AMOUNT, lockEnd);
        vm.stopPrank();
        
        // Verify stake
        assertEq(veToken.ownerOf(tokenId), alice);
        assertEq(veToken.getActiveTokenId(alice), tokenId);
        
        (uint256 stakedAmount, uint256 actualLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(stakedAmount, STAKE_AMOUNT);
        assertGt(actualLockEnd, 0);
        
        // Verify ZKC transfer
        assertEq(zkc.balanceOf(alice), AMOUNT * 10 - STAKE_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), STAKE_AMOUNT);
    }

    // Test staking with permit
    function testStakeWithPermit() public {
        uint256 lockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2; // Half max time
        uint256 deadline = vm.getBlockTimestamp() + 1 hours;
        
        // Create permit signature
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            alicePrivateKey,
            alice,
            address(veToken),
            STAKE_AMOUNT,
            deadline
        );
        
        vm.prank(alice);
        uint256 tokenId = veToken.stakeWithPermit(STAKE_AMOUNT, lockEnd, deadline, v, r, s);
        
        // Verify stake (same as approval test)
        assertEq(veToken.ownerOf(tokenId), alice);
        assertEq(veToken.getActiveTokenId(alice), tokenId);
        
        (uint256 stakedAmount, uint256 actualLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(stakedAmount, STAKE_AMOUNT);
        assertGt(actualLockEnd, 0);
        
        // Verify ZKC transfer
        assertEq(zkc.balanceOf(alice), AMOUNT * 10 - STAKE_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), STAKE_AMOUNT);
    }

    // Test add to stake with approval
    function testAddToStakeWithApproval() public {
        // Initial stake
        uint256 lockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2; // Half max time
        
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 tokenId = veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Try to add to stake without additional approval (should fail)
        vm.expectRevert();
        veToken.addToStake(ADD_AMOUNT);
        
        // Now approve additional amount and add to stake (should succeed)
        zkc.approve(address(veToken), ADD_AMOUNT);
        veToken.addToStake(ADD_AMOUNT);
        vm.stopPrank();
        
        // Verify updated stake
        (uint256 stakedAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(stakedAmount, STAKE_AMOUNT + ADD_AMOUNT);
        
        // Verify ZKC transfer
        assertEq(zkc.balanceOf(alice), AMOUNT * 10 - STAKE_AMOUNT - ADD_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), STAKE_AMOUNT + ADD_AMOUNT);
    }

    // Test add to stake with permit
    function testAddToStakeWithPermit() public {
        // Initial stake with approval
        uint256 lockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2; // Half max time
        
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 tokenId = veToken.stake(STAKE_AMOUNT, lockEnd);
        vm.stopPrank();
        
        // Add to stake with permit
        uint256 deadline = vm.getBlockTimestamp() + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            alicePrivateKey,
            alice,
            address(veToken),
            ADD_AMOUNT,
            deadline
        );
        
        vm.prank(alice);
        veToken.addToStakeWithPermit(ADD_AMOUNT, deadline, v, r, s);
        
        // Verify updated stake
        (uint256 stakedAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(stakedAmount, STAKE_AMOUNT + ADD_AMOUNT);
        
        // Verify ZKC transfer
        assertEq(zkc.balanceOf(alice), AMOUNT * 10 - STAKE_AMOUNT - ADD_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), STAKE_AMOUNT + ADD_AMOUNT);
    }

    // Test unstaking before lock expiry (should fail)
    function testUnstakeBeforeLockExpiry() public {
        uint256 lockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2; // Half max time
        
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 tokenId = veToken.stake(STAKE_AMOUNT, lockEnd);
        
        // Try to unstake before expiry
        vm.expectRevert(abi.encodeWithSelector(IStaking.LockHasNotExpiredYet.selector));
        veToken.unstake();
        vm.stopPrank();
    }

    // Test unstaking after lock expiry
    function testUnstakeAfterLockExpiry() public {
        uint256 lockEnd = vm.getBlockTimestamp() + MIN_STAKE_TIME_S + 1 weeks; // Just over minimum
        
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 tokenId = veToken.stake(STAKE_AMOUNT, lockEnd);
        vm.stopPrank();
        
        // Get actual lock end from contract
        (, uint256 actualLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        
        // Fast forward past lock expiry
        vm.warp(actualLockEnd + 1);
        
        uint256 aliceBalanceBefore = zkc.balanceOf(alice);
        
        vm.prank(alice);
        veToken.unstake();
        
        // Verify unstake
        assertEq(veToken.getActiveTokenId(alice), 0);
        assertEq(zkc.balanceOf(alice), aliceBalanceBefore + STAKE_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), 0);
        
        // Verify NFT is burned
        vm.expectRevert();
        veToken.ownerOf(tokenId);
    }

    // Test stake -> unstake -> stake again cycle
    function testStakeUnstakeStakeAgainCycle() public {
        // First stake for minimum duration (use 0 to set minimum)
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT * 2);
        uint256 tokenId1 = veToken.stake(STAKE_AMOUNT, 0); // Use 0 for minimum duration
        vm.stopPrank();
        
        // Verify first stake
        assertEq(veToken.getActiveTokenId(alice), tokenId1);
        (uint256 stakedAmount1, uint256 actualLockEnd1) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(stakedAmount1, STAKE_AMOUNT);
        
        // Fast forward and unstake
        vm.warp(actualLockEnd1 + 1);
        vm.prank(alice);
        veToken.unstake();
        
        // Verify unstaked
        assertEq(veToken.getActiveTokenId(alice), 0);
        
        // Second stake for max time period
        vm.prank(alice);
        uint256 tokenId2 = veToken.stake(STAKE_AMOUNT, type(uint256).max); // Use max for maximum duration
        
        // Verify second stake
        assertEq(veToken.getActiveTokenId(alice), tokenId2);
        assertNotEq(tokenId1, tokenId2); // Should be different token IDs
        
        (uint256 stakedAmount2,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(stakedAmount2, STAKE_AMOUNT);
        
        // Verify voting power is close to staked amount (max lock = max voting power)
        uint256 votingPower = veToken.getVotes(alice);
        assertApproxEqRel(votingPower, STAKE_AMOUNT, 0.01e18); // Within 1% of stake amount
        
        // Verify ZKC balances are consistent
        assertEq(zkc.balanceOf(alice), AMOUNT * 10 - STAKE_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), STAKE_AMOUNT);
    }

    // Test permit vs approval gas efficiency (placeholder for manual gas testing)
    function testPermitVsApprovalComparison() public {
        uint256 lockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2; // Half max time
        uint256 deadline = vm.getBlockTimestamp() + 1 hours;
        
        // Test with approval (Alice)
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 tokenId1 = veToken.stake(STAKE_AMOUNT, lockEnd);
        vm.stopPrank();
        
        // Test with permit (Bob)
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            bobPrivateKey,
            bob,
            address(veToken),
            STAKE_AMOUNT,
            deadline
        );
        
        vm.prank(bob);
        uint256 tokenId2 = veToken.stakeWithPermit(STAKE_AMOUNT, lockEnd, deadline, v, r, s);
        
        // Both should work identically
        assertEq(veToken.ownerOf(tokenId1), alice);
        assertEq(veToken.ownerOf(tokenId2), bob);
        
        (uint256 aliceStake,) = veToken.getStakedAmountAndExpiry(alice);
        (uint256 bobStake,) = veToken.getStakedAmountAndExpiry(bob);
        assertEq(aliceStake, bobStake);
    }

    // Test permit signature validation
    function testPermitSignatureValidation() public {
        uint256 lockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2; // Half max time
        uint256 deadline = vm.getBlockTimestamp() + 1 hours;
        
        // Create valid signature
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            alicePrivateKey,
            alice,
            address(veToken),
            STAKE_AMOUNT,
            deadline
        );
        
        // Test with wrong signature (should fail)
        vm.prank(alice);
        vm.expectRevert();
        veToken.stakeWithPermit(STAKE_AMOUNT, lockEnd, deadline, v, r, bytes32(uint256(s) + 1));
    }

    // Test permit deadline validation
    function testPermitDeadlineValidation() public {
        uint256 lockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2; // Half max time
        uint256 deadline = vm.getBlockTimestamp() - 1; // Past deadline
        
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            alicePrivateKey,
            alice,
            address(veToken),
            STAKE_AMOUNT,
            deadline
        );
        
        // Should fail with expired deadline
        vm.prank(alice);
        vm.expectRevert();
        veToken.stakeWithPermit(STAKE_AMOUNT, lockEnd, deadline, v, r, s);
    }

    

    // Test complex flow: stake -> unstake -> addToStake (fail) -> stake -> expire -> addToStake (voting power 0) -> extend lock (voting power > 0)
    function testComplexStakeFlowWithExpiry() public {
        // 1. Initial stake
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT * 3);
        uint256 tokenId1 = veToken.stake(STAKE_AMOUNT, 0); // Minimum duration
        vm.stopPrank();
        
        // Get actual lock end
        (, uint256 lockEnd1) = veToken.getStakedAmountAndExpiry(alice);
        
        // 2. Unstake after expiry
        vm.warp(lockEnd1 + 1);
        vm.prank(alice);
        veToken.unstake();
        
        // Verify unstaked
        assertEq(veToken.getActiveTokenId(alice), 0);
        
        // 3. Try to add to stake (should fail - no active position)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IStaking.NoActivePosition.selector));
        veToken.addToStake(ADD_AMOUNT);
        
        // 4. Stake again
        vm.prank(alice);
        uint256 tokenId2 = veToken.stake(STAKE_AMOUNT, 0); // Minimum duration again
        
        // Get new lock end
        (, uint256 lockEnd2) = veToken.getStakedAmountAndExpiry(alice);
        
        // 5. Let it expire (don't unstake)
        vm.warp(lockEnd2 + 1);
        
        // 6. Verify voting power is 0 after expiry
        uint256 votingPowerExpired = veToken.getVotes(alice);
        assertEq(votingPowerExpired, 0, "Voting power should be 0 after expiry");
        
        // 7. Try to add to expired stake (should fail now)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IStaking.CannotAddToExpiredPosition.selector));
        veToken.addToStake(ADD_AMOUNT);
        
        // Verify amount hasn't changed
        (uint256 amountAfterFailedAdd,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(amountAfterFailedAdd, STAKE_AMOUNT, "Amount should not change after failed add");
        
        // 8. Extend the expired lock first (this should work and restore voting power)
        uint256 newLockEnd = vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2; // Half max time
        vm.prank(alice);
        veToken.extendStakeLockup(newLockEnd);
        
        // 9. Verify voting power is now > 0
        uint256 votingPowerAfterExtension = veToken.getVotes(alice);
        assertGt(votingPowerAfterExtension, 0, "Voting power should be > 0 after extending expired lock");
        
        // 10. Now we can add to the re-activated position
        vm.prank(alice);
        veToken.addToStake(ADD_AMOUNT);
        
        // Verify amount increased
        (uint256 finalAmount, uint256 finalLockEnd) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(finalAmount, STAKE_AMOUNT + ADD_AMOUNT, "Final amount should include both stake and add");
    }

    // Test donation functionality - user adding stake to another user's position
    function testDonationByTokenId() public {
        // Set up approvals for donation test
        vm.prank(bob);
        zkc.approve(address(veToken), type(uint256).max);
        
        // Alice stakes first
        vm.startPrank(alice);
        zkc.approve(address(veToken), type(uint256).max);
        uint256 aliceTokenId = veToken.stake(STAKE_AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        // Get Alice's initial state
        (uint256 aliceInitialAmount,) = veToken.getStakedAmountAndExpiry(alice);
        uint256 aliceInitialVotingPower = veToken.getVotes(alice);
        uint256 aliceInitialRewardPower = veToken.getRewards(alice);
        
        assertEq(aliceInitialAmount, STAKE_AMOUNT, "Alice initial amount");
        assertGt(aliceInitialVotingPower, 0, "Alice should have voting power");
        assertEq(aliceInitialRewardPower, STAKE_AMOUNT, "Alice initial reward power");
        
        // Bob donates to Alice's position
        vm.prank(bob);
        veToken.addToStakeByTokenId(aliceTokenId, ADD_AMOUNT);
        
        // Verify Alice's position increased
        (uint256 aliceUpdatedAmount,) = veToken.getStakedAmountAndExpiry(alice);
        uint256 aliceUpdatedVotingPower = veToken.getVotes(alice);
        uint256 aliceUpdatedRewardPower = veToken.getRewards(alice);
        
        assertEq(aliceUpdatedAmount, STAKE_AMOUNT + ADD_AMOUNT, "Alice amount should increase");
        assertGt(aliceUpdatedVotingPower, aliceInitialVotingPower, "Alice voting power should increase");
        assertEq(aliceUpdatedRewardPower, STAKE_AMOUNT + ADD_AMOUNT, "Alice reward power should increase");
        
        // Verify Bob's balance decreased but he has no position
        assertEq(zkc.balanceOf(bob), AMOUNT * 10 - ADD_AMOUNT, "Bob's balance should decrease");
        assertEq(veToken.getActiveTokenId(bob), 0, "Bob should have no active position");
        assertEq(veToken.getVotes(bob), 0, "Bob should have no voting power");
        assertEq(veToken.getRewards(bob), 0, "Bob should have no reward power");
    }

    // Test donation with permit
    function testDonationWithPermitByTokenId() public {
        // Alice stakes first (set up approval for alice only)
        vm.startPrank(alice);
        zkc.approve(address(veToken), type(uint256).max);
        uint256 aliceTokenId = veToken.stake(STAKE_AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        // Get Alice's initial amount
        (uint256 aliceInitialAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(aliceInitialAmount, STAKE_AMOUNT, "Alice initial amount");
        
        // Bob donates using permit
        uint256 deadline = vm.getBlockTimestamp() + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            bobPrivateKey,
            bob,
            address(veToken),
            ADD_AMOUNT,
            deadline
        );
        
        vm.prank(bob);
        veToken.addToStakeWithPermitByTokenId(aliceTokenId, ADD_AMOUNT, deadline, v, r, s);
        
        // Verify Alice's position increased
        (uint256 aliceUpdatedAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(aliceUpdatedAmount, STAKE_AMOUNT + ADD_AMOUNT, "Alice amount should increase from donation");
        
        // Verify Bob has no position
        assertEq(veToken.getActiveTokenId(bob), 0, "Bob should have no active position");
    }

    // Test donation to expired position fails
    function testDonationToExpiredPositionFails() public {
        // Set up approvals
        vm.prank(alice);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(bob);
        zkc.approve(address(veToken), type(uint256).max);
        
        // Alice stakes with minimum duration
        vm.startPrank(alice);
        uint256 aliceTokenId = veToken.stake(STAKE_AMOUNT, 0);
        vm.stopPrank();
        
        // Get lock end and let it expire
        (, uint256 lockEnd) = veToken.getStakedAmountAndExpiry(alice);
        vm.warp(lockEnd + 1);
        
        // Verify Alice's position is expired (0 voting power)
        assertEq(veToken.getVotes(alice), 0, "Alice voting power should be 0 after expiry");
        assertEq(veToken.getRewards(alice), STAKE_AMOUNT, "Alice reward power should remain");
        
        // Bob tries to donate to Alice's expired position (should fail)
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IStaking.CannotAddToExpiredPosition.selector));
        veToken.addToStakeByTokenId(aliceTokenId, ADD_AMOUNT);
        
        // Verify Alice's amounts haven't changed
        (uint256 aliceUpdatedAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(aliceUpdatedAmount, STAKE_AMOUNT, "Alice amount should not change");
        assertEq(veToken.getVotes(alice), 0, "Alice voting power should still be 0");
        assertEq(veToken.getRewards(alice), STAKE_AMOUNT, "Alice reward power should not change");
    }

    // Test donation to non-existent token fails
    function testDonationToNonExistentTokenFails() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IStaking.TokenDoesNotExist.selector));
        veToken.addToStakeByTokenId(999, ADD_AMOUNT);
    }

    // Test multiple users donating to same position
    function testMultipleDonationsToSamePosition() public {
        // Set up approvals for all users
        vm.prank(alice);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(bob);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(charlie);
        zkc.approve(address(veToken), type(uint256).max);
        
        // Alice stakes first
        vm.startPrank(alice);
        uint256 aliceTokenId = veToken.stake(STAKE_AMOUNT, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 2);
        vm.stopPrank();
        
        // Bob stakes his own position first, then donates to Alice
        vm.startPrank(bob);
        uint256 bobTokenId = veToken.stake(STAKE_AMOUNT * 2, vm.getBlockTimestamp() + MAX_STAKE_TIME_S / 4);
        veToken.addToStakeByTokenId(aliceTokenId, ADD_AMOUNT);
        vm.stopPrank();
        
        // Charlie also donates
        vm.prank(charlie);
        veToken.addToStakeByTokenId(aliceTokenId, ADD_AMOUNT);
        
        // Verify Alice's position has both donations
        (uint256 aliceUpdatedAmount,) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(aliceUpdatedAmount, STAKE_AMOUNT + ADD_AMOUNT + ADD_AMOUNT, "Alice should have received both donations");
            
        // Verify Alice's powers increased accordingly
        uint256 aliceVotingPower = veToken.getVotes(alice);
        uint256 aliceRewardPower = veToken.getRewards(alice);
        assertGt(aliceVotingPower, 0, "Alice should have voting power");
        assertEq(aliceRewardPower, STAKE_AMOUNT + ADD_AMOUNT + ADD_AMOUNT, "Alice reward power should reflect total amount");
        
        // Verify Bob still has his own position but Charlie has no position
        assertEq(veToken.getActiveTokenId(bob), bobTokenId, "Bob should have his own position");
        assertEq(veToken.getActiveTokenId(charlie), 0, "Charlie should have no position");
        assertGt(veToken.getVotes(bob), 0, "Bob should have voting power from his own stake");
        assertGt(veToken.getRewards(bob), 0, "Bob should have reward power from his own stake");
        assertEq(veToken.getVotes(charlie), 0, "Charlie should have no voting power");
        assertEq(veToken.getRewards(charlie), 0, "Charlie should have no reward power");
    }
}