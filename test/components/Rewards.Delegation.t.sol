// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../veZKC.t.sol";
import "../../src/interfaces/IRewards.sol";
import "../../src/interfaces/IStaking.sol";
import "../../src/interfaces/IVotes.sol";
import "../../src/libraries/Constants.sol";
import {console2} from "forge-std/Test.sol";

contract RewardsDelegationTest is veZKCTest {
    address public constant CHARLIE = address(3);
    address public constant DAVE = address(4);

    function setUp() public override {
        super.setUp();

        // Setup additional accounts
        deal(address(zkc), CHARLIE, AMOUNT * 10);
        deal(address(zkc), DAVE, AMOUNT * 10);

        vm.prank(CHARLIE);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(DAVE);
        zkc.approve(address(veToken), type(uint256).max);
    }

    // Basic reward delegation tests

    function testSelfRewardDelegationByDefault() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Check Alice delegates rewards to herself by default
        assertEq(veToken.rewardDelegates(alice), alice, "Should self-delegate rewards by default");
        assertEq(
            veToken.getStakingRewards(alice),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Should have reward power equal to stake/scalar"
        );
    }

    function testSimpleRewardDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Check delegation
        assertEq(veToken.rewardDelegates(alice), bob, "Alice should delegate rewards to Bob");
        assertEq(veToken.getStakingRewards(alice), 0, "Alice should have no reward power");
        assertEq(
            veToken.getStakingRewards(bob),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have Alice's reward power"
        );
    }

    function testRewardDelegationChangeUpdatesRewards() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);
        assertEq(
            veToken.getStakingRewards(bob),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have Alice's reward power"
        );

        // Alice re-delegates rewards to Charlie
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        assertEq(veToken.rewardDelegates(alice), CHARLIE, "Alice should delegate rewards to Charlie");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no reward power");
        assertEq(
            veToken.getStakingRewards(CHARLIE),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Charlie should have Alice's reward power"
        );
    }

    function testMultipleRewardDelegators() public {
        // Alice and Bob stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT * 2);

        // Both delegate rewards to Charlie
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);
        vm.prank(bob);
        veToken.delegateRewards(CHARLIE);

        // Charlie should have combined reward power
        uint256 expectedRewards = (AMOUNT * 3) / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getStakingRewards(CHARLIE), expectedRewards, "Charlie should have combined reward power");
        assertEq(veToken.getStakingRewards(alice), 0, "Alice should have no reward power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no reward power");
    }

    function testDelegateRewardsBackToSelf() public {
        // Alice stakes and delegates rewards to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        assertEq(
            veToken.getStakingRewards(bob),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have Alice's reward power"
        );

        // Alice delegates rewards back to herself
        vm.prank(alice);
        veToken.delegateRewards(alice);

        assertEq(veToken.rewardDelegates(alice), alice, "Alice should delegate rewards to herself");
        assertEq(
            veToken.getStakingRewards(alice),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Alice should have her reward power back"
        );
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no reward power");
    }

    function testAddToStakeWithRewardDelegation() public {
        // Alice stakes and delegates rewards to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        assertEq(
            veToken.getStakingRewards(bob),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have initial reward power"
        );

        // Alice adds to her stake
        vm.prank(alice);
        veToken.addToStake(AMOUNT);

        // Bob's reward power should increase
        assertEq(
            veToken.getStakingRewards(bob),
            (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR,
            "Bob should have increased reward power"
        );
        assertEq(veToken.getStakingRewards(alice), 0, "Alice should still have no reward power");
    }

    // Independent delegation tests (rewards vs votes)

    function testIndependentRewardAndVoteDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice delegates votes to Bob and rewards to Charlie
        vm.prank(alice);
        veToken.delegate(bob);
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Check independent delegation
        assertEq(veToken.delegates(alice), bob, "Alice should delegate votes to Bob");
        assertEq(veToken.rewardDelegates(alice), CHARLIE, "Alice should delegate rewards to Charlie");

        // Check power distribution
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have voting power");
        assertEq(veToken.getVotes(CHARLIE), 0, "Charlie should have no voting power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no reward power");
        assertEq(
            veToken.getStakingRewards(CHARLIE),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Charlie should have reward power"
        );
    }

    function testSwitchRewardDelegationIndependently() public {
        // Alice stakes and sets up initial delegations
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Switch only reward delegation to Charlie
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Votes should stay with Bob, rewards move to Charlie
        assertEq(veToken.delegates(alice), bob, "Votes should still be delegated to Bob");
        assertEq(veToken.rewardDelegates(alice), CHARLIE, "Rewards should be delegated to Charlie");
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should keep voting power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should lose reward power");
        assertEq(
            veToken.getStakingRewards(CHARLIE),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Charlie should gain reward power"
        );
    }

    // PoVW reward cap tests

    function testPoVWRewardCapDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Check initial PoVW cap
        uint256 expectedCap = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(veToken.getPoVWRewardCap(alice), expectedCap, "Alice should have PoVW cap");

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // PoVW cap should move with reward delegation
        assertEq(veToken.getPoVWRewardCap(alice), 0, "Alice should have no PoVW cap");
        assertEq(veToken.getPoVWRewardCap(bob), expectedCap, "Bob should have Alice's PoVW cap");
    }

    // Historical reward delegation tests

    function testHistoricalRewardPowerAfterDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        uint256 checkpoint1 = vm.getBlockTimestamp();

        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 checkpoint2 = vm.getBlockTimestamp();

        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Alice delegates rewards to Charlie
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Check historical reward power
        assertEq(
            veToken.getPastStakingRewards(alice, checkpoint1),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Alice should have had reward power at checkpoint1"
        );
        assertEq(
            veToken.getPastStakingRewards(bob, checkpoint1), 0, "Bob should have had no reward power at checkpoint1"
        );

        assertEq(
            veToken.getPastStakingRewards(alice, checkpoint2), 0, "Alice should have had no reward power at checkpoint2"
        );
        assertEq(
            veToken.getPastStakingRewards(bob, checkpoint2),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have had reward power at checkpoint2"
        );
        assertEq(
            veToken.getPastStakingRewards(CHARLIE, checkpoint2),
            0,
            "Charlie should have had no reward power at checkpoint2"
        );
    }

    function testHistoricalPoVWCapAfterDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        uint256 checkpoint1 = vm.getBlockTimestamp();
        uint256 expectedCap = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;

        // Advance time and delegate
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 checkpoint2 = vm.getBlockTimestamp();

        // Advance time to make checkpoint2 a past timestamp
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Check historical PoVW caps
        assertEq(
            veToken.getPastPoVWRewardCap(alice, checkpoint1),
            expectedCap,
            "Alice should have had PoVW cap at checkpoint1"
        );
        assertEq(veToken.getPastPoVWRewardCap(bob, checkpoint1), 0, "Bob should have had no PoVW cap at checkpoint1");

        assertEq(veToken.getPastPoVWRewardCap(alice, checkpoint2), 0, "Alice should have no PoVW cap at checkpoint2");
        assertEq(veToken.getPastPoVWRewardCap(bob, checkpoint2), expectedCap, "Bob should have PoVW cap at checkpoint2");
    }

    function testHistoricalTotalRewardsUnaffectedByDelegation() public {
        // Alice and Bob stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT);

        uint256 totalBefore = veToken.getTotalStakingRewards();

        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 totalAfter = veToken.getTotalStakingRewards();

        // Total rewards should remain unchanged
        uint256 expectedTotal = (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR;
        assertEq(totalBefore, expectedTotal, "Total rewards before delegation");
        assertEq(totalAfter, expectedTotal, "Total rewards after delegation");
    }

    // Edge cases and error conditions

    function testCannotDelegateRewardsWithoutPosition() public {
        // Try to delegate rewards without staking
        vm.prank(alice);
        vm.expectRevert(IStaking.NoActivePosition.selector);
        veToken.delegateRewards(bob);
    }

    function testCannotDelegateRewardsWhileWithdrawing() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice initiates unstake
        vm.prank(alice);
        veToken.initiateUnstake();

        // Try to delegate rewards while withdrawing
        vm.prank(alice);
        vm.expectRevert(IVotes.CannotDelegateWhileWithdrawing.selector);
        veToken.delegateRewards(bob);
    }

    function testCannotInitiateUnstakeWithActiveRewardDelegation() public {
        // Alice stakes and delegates rewards to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Try to initiate unstake with active reward delegation
        vm.prank(alice);
        vm.expectRevert(IStaking.MustUndelegateRewardsFirst.selector);
        veToken.initiateUnstake();

        // Undelegate rewards first
        vm.prank(alice);
        veToken.delegateRewards(alice);

        // Now can initiate unstake
        vm.prank(alice);
        veToken.initiateUnstake();
    }

    function testRewardDelegationToZeroAddress() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Delegate rewards to zero address (should work - represents self-delegation)
        vm.prank(alice);
        veToken.delegateRewards(address(0));

        // Should be same as self-delegation
        assertEq(veToken.rewardDelegates(alice), alice, "Should delegate rewards to self when delegating to zero");
        assertEq(veToken.getStakingRewards(alice), AMOUNT / Constants.REWARD_POWER_SCALAR, "Should have reward power");
    }

    function testRewardDelegationSameAddress() public {
        // Alice stakes and delegates rewards to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 bobRewardsBefore = veToken.getStakingRewards(bob);

        // Delegate rewards to Bob again (should be no-op)
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 bobRewardsAfter = veToken.getStakingRewards(bob);

        assertEq(bobRewardsBefore, bobRewardsAfter, "Rewards should not change when delegating to same address");
        assertEq(veToken.rewardDelegates(alice), bob, "Delegation should remain the same");
    }

    // Events testing

    function testRewardDelegationEvents() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Test reward delegation event

        vm.prank(alice);
        veToken.delegateRewards(bob);
    }

    // Gas optimization tests

    function testGasOptimizationMultipleRewardDelegations() public {
        // Setup multiple stakers
        uint256 numStakers = 10;
        for (uint256 i = 1; i <= numStakers; i++) {
            address staker = address(uint160(i + 100));
            deal(address(zkc), staker, AMOUNT);
            vm.prank(staker);
            zkc.approve(address(veToken), type(uint256).max);
            vm.prank(staker);
            veToken.stake(AMOUNT);
        }

        // Measure gas for reward delegations
        uint256 totalGas = 0;
        for (uint256 i = 1; i <= numStakers; i++) {
            address staker = address(uint160(i + 100));
            uint256 gasBefore = gasleft();
            vm.prank(staker);
            veToken.delegateRewards(CHARLIE);
            uint256 gasUsed = gasBefore - gasleft();
            totalGas += gasUsed;
        }

        uint256 avgGas = totalGas / numStakers;
        console2.log("Average gas per reward delegation:", avgGas);

        // Charlie should have all reward power
        uint256 expectedRewards = (AMOUNT * numStakers) / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getStakingRewards(CHARLIE), expectedRewards, "Charlie should have all delegated reward power");
    }
}
