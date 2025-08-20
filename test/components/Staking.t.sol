// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../veZKC.t.sol";
import "../../src/interfaces/IStaking.sol";
import "../../src/libraries/Constants.sol";
import "../../src/libraries/StakeManager.sol";

contract veZKCStakeTest is veZKCTest {
    uint256 constant STAKE_AMOUNT = 10_000 * 10 ** 18;
    uint256 constant ADD_AMOUNT = 5_000 * 10 ** 18;

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
        vm.startPrank(alice);

        // First try staking without approval (should fail with ERC20 error)
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientAllowance(address,uint256,uint256)", address(veToken), 0, STAKE_AMOUNT
            )
        );
        veToken.stake(STAKE_AMOUNT);

        // Now approve and stake (should succeed)
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 tokenId = veToken.stake(STAKE_AMOUNT);
        vm.snapshotGasLastCall("stake: Basic staking with approval");
        vm.stopPrank();

        // Verify stake
        assertEq(veToken.ownerOf(tokenId), alice);
        assertEq(veToken.getActiveTokenId(alice), tokenId);

        (uint256 stakedAmount, uint256 withdrawableAt) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(stakedAmount, STAKE_AMOUNT);
        assertEq(withdrawableAt, 0); // No withdrawal initiated

        // Verify ZKC transfer
        assertEq(zkc.balanceOf(alice), AMOUNT * 10 - STAKE_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), STAKE_AMOUNT);
    }

    // Test staking with permit
    function testStakeWithPermit() public {
        uint256 deadline = vm.getBlockTimestamp() + 1 hours;

        // Create permit signature
        (uint8 v, bytes32 r, bytes32 s) =
            _createPermitSignature(alicePrivateKey, alice, address(veToken), STAKE_AMOUNT, deadline);

        vm.prank(alice);
        uint256 tokenId = veToken.stakeWithPermit(STAKE_AMOUNT, deadline, v, r, s);

        // Verify stake (same as approval test)
        assertEq(veToken.ownerOf(tokenId), alice);
        assertEq(veToken.getActiveTokenId(alice), tokenId);

        (uint256 stakedAmount, uint256 withdrawableAt) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(stakedAmount, STAKE_AMOUNT);
        assertEq(withdrawableAt, 0); // No withdrawal initiated

        // Verify ZKC transfer
        assertEq(zkc.balanceOf(alice), AMOUNT * 10 - STAKE_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), STAKE_AMOUNT);
    }

    // Test add to stake with approval
    function testAddToStakeWithApproval() public {
        // Initial stake
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 tokenId = veToken.stake(STAKE_AMOUNT);

        // Try to add without approval (should fail with ERC20 error)
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientAllowance(address,uint256,uint256)", address(veToken), 0, ADD_AMOUNT
            )
        );
        veToken.addToStake(ADD_AMOUNT);

        // Approve and add to stake
        zkc.approve(address(veToken), ADD_AMOUNT);
        veToken.addToStake(ADD_AMOUNT);
        vm.snapshotGasLastCall("addToStake: Adding to existing stake");
        vm.stopPrank();

        // Verify added stake
        (uint256 stakedAmount, uint256 withdrawableAt) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(stakedAmount, STAKE_AMOUNT + ADD_AMOUNT);
        assertEq(withdrawableAt, 0); // No withdrawal initiated

        // Verify ZKC transfers
        assertEq(zkc.balanceOf(alice), AMOUNT * 10 - STAKE_AMOUNT - ADD_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), STAKE_AMOUNT + ADD_AMOUNT);

        // Should still be same token ID
        assertEq(veToken.getActiveTokenId(alice), tokenId);
    }

    // Test add to stake with permit
    function testAddToStakeWithPermit() public {
        // Initial stake with permit
        uint256 deadline1 = vm.getBlockTimestamp() + 1 hours;

        (uint8 v1, bytes32 r1, bytes32 s1) =
            _createPermitSignature(alicePrivateKey, alice, address(veToken), STAKE_AMOUNT, deadline1);

        vm.prank(alice);
        uint256 tokenId = veToken.stakeWithPermit(STAKE_AMOUNT, deadline1, v1, r1, s1);

        // Add to stake with permit
        uint256 deadline2 = vm.getBlockTimestamp() + 1 hours;

        (uint8 v2, bytes32 r2, bytes32 s2) =
            _createPermitSignature(alicePrivateKey, alice, address(veToken), ADD_AMOUNT, deadline2);

        vm.prank(alice);
        veToken.addToStakeWithPermit(ADD_AMOUNT, deadline2, v2, r2, s2);

        // Verify added stake
        (uint256 stakedAmount, uint256 withdrawableAt) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(stakedAmount, STAKE_AMOUNT + ADD_AMOUNT);
        assertEq(withdrawableAt, 0); // No withdrawal initiated

        // Should still be same token ID
        assertEq(veToken.getActiveTokenId(alice), tokenId);
    }

    // Test add to stake by token ID (donation)
    function testAddToStakeByTokenId() public {
        // Alice stakes
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 aliceTokenId = veToken.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Bob adds to Alice's stake (donation)
        vm.startPrank(bob);
        zkc.approve(address(veToken), ADD_AMOUNT);
        veToken.addToStakeByTokenId(aliceTokenId, ADD_AMOUNT);
        vm.snapshotGasLastCall("addToStakeByTokenId: Adding to another user's stake");
        vm.stopPrank();

        // Verify Alice received the additional stake
        (uint256 stakedAmount, uint256 withdrawableAt) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(stakedAmount, STAKE_AMOUNT + ADD_AMOUNT);
        assertEq(withdrawableAt, 0);

        // Verify Bob's tokens were used
        assertEq(zkc.balanceOf(bob), AMOUNT * 10 - ADD_AMOUNT);

        // Alice still owns the token
        assertEq(veToken.ownerOf(aliceTokenId), alice);
    }

    // Test withdrawal workflow
    function testWithdrawalWorkflow() public {
        // Alice stakes
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 tokenId = veToken.stake(STAKE_AMOUNT);

        // Check initial voting power
        uint256 initialVotingPower = veToken.getVotes(alice);
        assertEq(initialVotingPower, STAKE_AMOUNT); // 1:1 ratio with scalar = 1

        // Initiate withdrawal
        veToken.initiateUnstake();
        vm.snapshotGasLastCall("initiateUnstake: Starting withdrawal process");

        // Check withdrawal was initiated
        (uint256 stakedAmount, uint256 withdrawableAt) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(stakedAmount, STAKE_AMOUNT); // Amount unchanged
        assertEq(withdrawableAt, vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD);

        // Voting power should drop to 0 immediately
        assertEq(veToken.getVotes(alice), 0);

        // Cannot complete withdrawal immediately
        vm.expectRevert(StakeManager.WithdrawalPeriodNotComplete.selector);
        veToken.completeUnstake();

        // Warp forward past withdrawal period
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);

        // Now can complete withdrawal
        uint256 balanceBefore = zkc.balanceOf(alice);
        veToken.completeUnstake();
        vm.snapshotGasLastCall("completeUnstake: Completing withdrawal and burning NFT");
        vm.stopPrank();

        // Verify withdrawal completed
        assertEq(zkc.balanceOf(alice), balanceBefore + STAKE_AMOUNT);
        assertEq(zkc.balanceOf(address(veToken)), 0);

        // Token should be burned - check with specific error
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", tokenId));
        veToken.ownerOf(tokenId);

        // No active position
        assertEq(veToken.getActiveTokenId(alice), 0);

        (uint256 finalStakedAmount, uint256 finalWithdrawableAt) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(finalStakedAmount, 0);
        assertEq(finalWithdrawableAt, 0);
    }

    // Test cannot add to stake while withdrawing
    function testCannotAddToStakeWhileWithdrawing() public {
        vm.startPrank(alice);

        // Initial stake
        zkc.approve(address(veToken), STAKE_AMOUNT);
        veToken.stake(STAKE_AMOUNT);

        // Initiate withdrawal
        veToken.initiateUnstake();

        // Try to add to stake (should fail with specific error)
        zkc.approve(address(veToken), ADD_AMOUNT);
        vm.expectRevert(StakeManager.CannotAddToWithdrawingPosition.selector);
        veToken.addToStake(ADD_AMOUNT);

        vm.stopPrank();
    }

    // Test cannot stake if already have active position
    function testCannotStakeWithActivePosition() public {
        vm.startPrank(alice);

        // Initial stake
        zkc.approve(address(veToken), STAKE_AMOUNT);
        veToken.stake(STAKE_AMOUNT);

        // Try to stake again (should fail with specific error)
        zkc.approve(address(veToken), STAKE_AMOUNT);
        vm.expectRevert(StakeManager.UserAlreadyHasActivePosition.selector);
        veToken.stake(STAKE_AMOUNT);

        vm.stopPrank();
    }

    // Test cannot initiate withdrawal without active position
    function testCannotInitiateWithdrawalWithoutPosition() public {
        vm.startPrank(alice);

        // Try to initiate withdrawal without staking first
        vm.expectRevert(IStaking.NoActivePosition.selector);
        veToken.initiateUnstake();

        vm.stopPrank();
    }

    // Test cannot complete withdrawal without initiating
    function testCannotCompleteWithdrawalWithoutInitiating() public {
        vm.startPrank(alice);

        // Stake first
        zkc.approve(address(veToken), STAKE_AMOUNT);
        veToken.stake(STAKE_AMOUNT);

        // Try to complete withdrawal without initiating
        vm.expectRevert(StakeManager.WithdrawalNotInitiated.selector);
        veToken.completeUnstake();

        vm.stopPrank();
    }

    // Test cannot initiate withdrawal twice
    function testCannotInitiateWithdrawalTwice() public {
        vm.startPrank(alice);

        // Stake and initiate withdrawal
        zkc.approve(address(veToken), STAKE_AMOUNT);
        veToken.stake(STAKE_AMOUNT);
        veToken.initiateUnstake();

        // Try to initiate again (should fail)
        vm.expectRevert(StakeManager.WithdrawalAlreadyInitiated.selector);
        veToken.initiateUnstake();

        vm.stopPrank();
    }

    // Test zero amount staking
    function testCannotStakeZeroAmount() public {
        vm.startPrank(alice);

        zkc.approve(address(veToken), 0);
        vm.expectRevert(StakeManager.ZeroAmount.selector);
        veToken.stake(0);

        vm.stopPrank();
    }

    // Test zero amount add to stake
    function testCannotAddZeroAmountToStake() public {
        vm.startPrank(alice);

        // Initial stake
        zkc.approve(address(veToken), STAKE_AMOUNT);
        veToken.stake(STAKE_AMOUNT);

        // Try to add zero amount
        zkc.approve(address(veToken), 0);
        vm.expectRevert(StakeManager.ZeroAmount.selector);
        veToken.addToStake(0);

        vm.stopPrank();
    }

    // Test multiple users staking
    function testMultipleUsersStaking() public {
        // Alice stakes
        vm.startPrank(alice);
        zkc.approve(address(veToken), STAKE_AMOUNT);
        uint256 aliceTokenId = veToken.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Bob stakes
        vm.startPrank(bob);
        zkc.approve(address(veToken), STAKE_AMOUNT * 2);
        uint256 bobTokenId = veToken.stake(STAKE_AMOUNT * 2);
        vm.stopPrank();

        // Verify separate positions
        assertEq(veToken.getActiveTokenId(alice), aliceTokenId);
        assertEq(veToken.getActiveTokenId(bob), bobTokenId);
        assertTrue(aliceTokenId != bobTokenId);

        // Verify individual stakes
        (uint256 aliceAmount,) = veToken.getStakedAmountAndWithdrawalTime(alice);
        (uint256 bobAmount,) = veToken.getStakedAmountAndWithdrawalTime(bob);

        assertEq(aliceAmount, STAKE_AMOUNT);
        assertEq(bobAmount, STAKE_AMOUNT * 2);

        // Verify voting powers
        assertEq(veToken.getVotes(alice), STAKE_AMOUNT);
        assertEq(veToken.getVotes(bob), STAKE_AMOUNT * 2);

        // Verify total voting supply by checking votes at current time (after both stakes)
        uint256 currentTime = vm.getBlockTimestamp();
        vm.warp(currentTime + 1);
        assertEq(veToken.getPastTotalSupply(currentTime), STAKE_AMOUNT + STAKE_AMOUNT * 2);
    }

    // Test unstaking then restaking creates new token ID
    function testUnstakeAndRestake() public {
        vm.startPrank(alice);

        // Initial stake
        zkc.approve(address(veToken), STAKE_AMOUNT * 2);
        uint256 firstTokenId = veToken.stake(STAKE_AMOUNT);

        // Verify initial state
        assertEq(veToken.getActiveTokenId(alice), firstTokenId);
        assertEq(veToken.getVotes(alice), STAKE_AMOUNT);
        assertEq(firstTokenId, 1);

        // Complete withdrawal workflow
        veToken.initiateUnstake();
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);
        veToken.completeUnstake();

        // Verify withdrawal completed
        assertEq(veToken.getActiveTokenId(alice), 0);
        assertEq(veToken.getVotes(alice), 0);

        // First token should be burned
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", firstTokenId));
        veToken.ownerOf(firstTokenId);

        // Create new stake position
        uint256 secondTokenId = veToken.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Verify new token ID is different (incremented)
        assertGt(secondTokenId, firstTokenId);
        assertEq(secondTokenId, 2);

        // Verify new position is active
        assertEq(veToken.getActiveTokenId(alice), secondTokenId);
        assertEq(veToken.getVotes(alice), STAKE_AMOUNT);
        assertEq(veToken.ownerOf(secondTokenId), alice);

        (uint256 stakedAmount, uint256 withdrawableAt) = veToken.getStakedAmountAndWithdrawalTime(alice);
        assertEq(stakedAmount, STAKE_AMOUNT);
        assertEq(withdrawableAt, 0); // Not withdrawing
    }

    // Note: _createPermitSignature is inherited from veZKCTest base contract
}
