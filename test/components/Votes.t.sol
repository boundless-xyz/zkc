// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../veZKC.t.sol";
import "../../src/interfaces/IStaking.sol";
import "../../src/libraries/Constants.sol";

contract veZKCVotesTest is veZKCTest {
    function testGetVotesConstantOverTime() public {
        // Alice stakes
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        // Initial voting power should be 1:1 with staked amount (scalar = 1)
        uint256 initialPower = veToken.getVotes(alice);
        vm.snapshotGasLastCall("getVotes: Getting current voting power");
        assertEq(initialPower, AMOUNT);

        // After some time passes, power should remain the same (no decay)
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        uint256 laterPower = veToken.getVotes(alice);
        assertEq(laterPower, AMOUNT);

        // Even after years, power should remain constant
        vm.warp(vm.getBlockTimestamp() + 4 * 365 days);
        uint256 muchLaterPower = veToken.getVotes(alice);
        assertEq(muchLaterPower, AMOUNT);
    }

    function testGetPastVotesHistoricalAccuracy() public {
        // Record initial timestamp
        uint256 t0 = vm.getBlockTimestamp();

        // Alice stakes at t0
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        uint256 t1 = vm.getBlockTimestamp();

        // Warp forward and check historical voting power
        vm.warp(t1 + 10 weeks);
        uint256 t2 = vm.getBlockTimestamp();

        // Past votes at t1 should equal staked amount
        uint256 pastVotesT1 = veToken.getPastVotes(alice, t1);
        vm.snapshotGasLastCall("getPastVotes: Getting historical voting power");
        assertEq(pastVotesT1, AMOUNT);

        // Current votes should still be the same
        uint256 currentVotes = veToken.getVotes(alice);
        assertEq(currentVotes, AMOUNT);

        // Warp even further forward
        vm.warp(t2 + 20 weeks);

        // Historical votes at both timestamps should remain consistent
        assertEq(veToken.getPastVotes(alice, t1), AMOUNT);
        assertEq(veToken.getPastVotes(alice, t2), AMOUNT);

        // Current votes should still be the same
        assertEq(veToken.getVotes(alice), AMOUNT);
    }

    function testVotingPowerDropsToZeroWhenWithdrawing() public {
        // Alice stakes
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);

        // Verify initial voting power
        uint256 initialPower = veToken.getVotes(alice);
        assertEq(initialPower, AMOUNT);

        // Initiate withdrawal
        veToken.initiateUnstake();

        // Voting power should immediately drop to 0
        uint256 withdrawingPower = veToken.getVotes(alice);
        assertEq(withdrawingPower, 0);

        // Even after time passes during withdrawal period, should remain 0
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD / 2);
        uint256 midWithdrawalPower = veToken.getVotes(alice);
        assertEq(midWithdrawalPower, 0);

        vm.stopPrank();
    }

    function testPastVotesBeforeAndAfterWithdrawal() public {
        // Alice stakes
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        uint256 t1 = vm.getBlockTimestamp();

        // Warp forward
        vm.warp(t1 + 5 weeks);
        uint256 t2 = vm.getBlockTimestamp();

        // Initiate withdrawal
        vm.prank(alice);
        veToken.initiateUnstake();

        // Warp forward more to make all timestamps past
        vm.warp(t2 + 1);

        // Past votes before withdrawal should still show full power
        assertEq(veToken.getPastVotes(alice, t1), AMOUNT);

        // Past votes after withdrawal initiation should show 0 power
        assertEq(veToken.getPastVotes(alice, t2), 0);

        // Current votes should be 0
        assertEq(veToken.getVotes(alice), 0);
    }

    function testTotalSupplyAccuracy() public {
        // Alice stakes
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        uint256 t1 = vm.getBlockTimestamp();

        // Move to next block and then Bob stakes
        vm.warp(t1 + 1);
        vm.startPrank(bob);
        zkc.approve(address(veToken), AMOUNT * 2);
        veToken.stake(AMOUNT * 2);
        vm.stopPrank();

        uint256 t2 = vm.getBlockTimestamp();

        // Warp forward to make both timestamps past
        vm.warp(t2 + 1);

        // Total supply after both should be sum of both stakes
        uint256 totalAfterBoth = veToken.getPastTotalSupply(t2);
        assertEq(totalAfterBoth, AMOUNT + AMOUNT * 2);

        // Historical total supply after alice only should just be alice's amount
        uint256 totalAfterAlice = veToken.getPastTotalSupply(t1);
        assertEq(totalAfterAlice, AMOUNT);
    }

    function testTotalSupplyWithWithdrawals() public {
        // Alice and Bob both stake
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        uint256 t1 = vm.getBlockTimestamp();

        // Move forward and Bob stakes
        vm.warp(t1 + 1);
        vm.startPrank(bob);
        zkc.approve(address(veToken), AMOUNT * 2);
        veToken.stake(AMOUNT * 2);
        vm.stopPrank();

        uint256 t2 = vm.getBlockTimestamp();

        // Move forward again and Alice initiates withdrawal
        vm.warp(t2 + 1);
        vm.prank(alice);
        veToken.initiateUnstake();

        uint256 t3 = vm.getBlockTimestamp();

        // Warp forward to make all timestamps past
        vm.warp(t3 + 1);

        // Total supply should drop to just Bob's stake after Alice withdrawal
        uint256 totalAfterAliceWithdrawal = veToken.getPastTotalSupply(t3);
        assertEq(totalAfterAliceWithdrawal, AMOUNT * 2);

        // Historical total supply before withdrawal should still show both
        assertEq(veToken.getPastTotalSupply(t2), AMOUNT + AMOUNT * 2);

        // Even earlier, should show just Alice
        assertEq(veToken.getPastTotalSupply(t1), AMOUNT);
    }

    function testVotingPowerScaling() public {
        // Test that voting power scales correctly with the scalar
        // Voting power = staked amount / VOTING_POWER_SCALAR

        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        // Voting power should equal staked amount divided by scalar
        uint256 votingPower = veToken.getVotes(alice);
        uint256 expectedPower = AMOUNT / Constants.VOTING_POWER_SCALAR;
        assertEq(votingPower, expectedPower, "Voting power should equal amount divided by VOTING_POWER_SCALAR");
    }

    function testMultipleUsersVotingPowers() public {
        // Alice stakes AMOUNT
        vm.startPrank(alice);
        zkc.approve(address(veToken), AMOUNT);
        veToken.stake(AMOUNT);
        vm.stopPrank();

        // Bob stakes 2x AMOUNT
        vm.startPrank(bob);
        zkc.approve(address(veToken), AMOUNT * 2);
        veToken.stake(AMOUNT * 2);
        vm.stopPrank();

        // Charlie stakes 0.5x AMOUNT
        vm.startPrank(charlie);
        zkc.approve(address(veToken), AMOUNT / 2);
        veToken.stake(AMOUNT / 2);
        vm.stopPrank();

        // Verify individual voting powers
        assertEq(veToken.getVotes(alice), AMOUNT);
        assertEq(veToken.getVotes(bob), AMOUNT * 2);
        assertEq(veToken.getVotes(charlie), AMOUNT / 2);

        // Verify they don't interfere with each other
        uint256 t1 = vm.getBlockTimestamp();
        vm.warp(t1 + 10 weeks);

        // Powers should remain the same
        assertEq(veToken.getVotes(alice), AMOUNT);
        assertEq(veToken.getVotes(bob), AMOUNT * 2);
        assertEq(veToken.getVotes(charlie), AMOUNT / 2);

        // Historical powers should also be correct
        assertEq(veToken.getPastVotes(alice, t1), AMOUNT);
        assertEq(veToken.getPastVotes(bob, t1), AMOUNT * 2);
        assertEq(veToken.getPastVotes(charlie, t1), AMOUNT / 2);
    }

    function testZeroVotesWhenNoStake() public {
        // User with no stake should have 0 voting power
        assertEq(veToken.getVotes(alice), 0);
        assertEq(veToken.getVotes(bob), 0);

        // Historical votes should also be 0 - warp forward first
        uint256 currentTime = vm.getBlockTimestamp();
        vm.warp(currentTime + 1);
        assertEq(veToken.getPastVotes(alice, currentTime), 0);
        assertEq(veToken.getPastVotes(bob, currentTime), 0);
    }
}
