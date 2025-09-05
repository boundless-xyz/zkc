// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../veZKC.t.sol";
import "../../src/interfaces/IVotes.sol";
import "../../src/interfaces/IRewards.sol";
import "../../src/interfaces/IStaking.sol";
import "../../src/libraries/Constants.sol";
import {IVotes as OZIVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract StakingDelegationTest is veZKCTest {
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

    function testCannotInitiateUnstakeWithVoteDelegation() public {
        // Alice stakes and delegates votes
        vm.prank(alice);
        
        // Expect events for initial stake (alice gets both voting and reward power)
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(alice, 0, AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IRewards.DelegateRewardsChanged(alice, 0, AMOUNT);
        
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);

        // Cannot initiate unstake while votes are delegated
        vm.prank(alice);
        vm.expectRevert(IStaking.MustUndelegateVotesFirst.selector);
        veToken.initiateUnstake();
    }

    function testCannotInitiateUnstakeWithRewardDelegation() public {
        // Alice stakes and delegates rewards
        vm.prank(alice);
        
        // Expect events for initial stake (alice gets both voting and reward power)
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(alice, 0, AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IRewards.DelegateRewardsChanged(alice, 0, AMOUNT);
        
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Cannot initiate unstake while rewards are delegated
        vm.prank(alice);
        vm.expectRevert(IStaking.MustUndelegateRewardsFirst.selector);
        veToken.initiateUnstake();
    }

    function testCannotInitiateUnstakeWithBothDelegations() public {
        // Alice stakes and delegates both votes and rewards
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Cannot initiate unstake with any delegation active
        vm.prank(alice);
        vm.expectRevert(IStaking.MustUndelegateVotesFirst.selector);
        veToken.initiateUnstake();

        // Undelegate votes but keep rewards delegated
        vm.prank(alice);
        veToken.delegate(alice);

        // Still cannot unstake with reward delegation
        vm.prank(alice);
        vm.expectRevert(IStaking.MustUndelegateRewardsFirst.selector);
        veToken.initiateUnstake();

        // Undelegate rewards too
        vm.prank(alice);
        veToken.delegateRewards(alice);

        // Now can initiate unstake
        vm.prank(alice);
        veToken.initiateUnstake();
    }

    function testCanUnstakeAfterUndelegating() public {
        // Store initial balance
        uint256 initialBalance = zkc.balanceOf(alice);

        // Alice stakes and delegates
        vm.prank(alice);
        
        // Expect events for initial stake (alice gets both voting and reward power)
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(alice, 0, AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IRewards.DelegateRewardsChanged(alice, 0, AMOUNT);
        
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Undelegate both
        vm.prank(alice);
        veToken.delegate(alice);
        vm.prank(alice);
        veToken.delegateRewards(alice);

        // Now can initiate unstake - expect events showing power reduction to 0
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(alice, AMOUNT, 0);
        vm.expectEmit(true, true, true, true);
        emit IRewards.DelegateRewardsChanged(alice, AMOUNT, 0);
        
        veToken.initiateUnstake();

        // Wait for withdrawal period
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD);

        // Complete unstake
        vm.prank(alice);
        veToken.completeUnstake();

        // Verify Alice got her tokens back
        assertEq(zkc.balanceOf(alice), initialBalance, "Alice should receive her tokens back");
    }

    function testCannotDelegateVotesWhileWithdrawing() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Initiate unstake
        vm.prank(alice);
        veToken.initiateUnstake();

        // Cannot delegate votes while withdrawing
        vm.prank(alice);
        vm.expectRevert(IVotes.CannotDelegateVotesWhileWithdrawing.selector);
        veToken.delegate(bob);
    }

    function testCannotDelegateRewardsWhileWithdrawing() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Initiate unstake
        vm.prank(alice);
        veToken.initiateUnstake();

        // Cannot delegate rewards while withdrawing
        vm.prank(alice);
        vm.expectRevert(IRewards.CannotDelegateRewardsWhileWithdrawing.selector);
        veToken.delegateRewards(bob);
    }

    // Tests for adding to stake with delegation

    function testAddToStakeIncreasesVoteDelegation() public {
        // Alice stakes and delegates votes to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);

        uint256 bobVotesBefore = veToken.getVotes(bob);
        assertEq(bobVotesBefore, AMOUNT, "Bob should have initial voting power");

        // Alice adds more stake
        vm.prank(alice);
        veToken.addToStake(AMOUNT);

        uint256 bobVotesAfter = veToken.getVotes(bob);
        assertEq(bobVotesAfter, AMOUNT * 2, "Bob should have increased voting power");
    }

    function testAddToStakeIncreasesRewardDelegation() public {
        // Alice stakes and delegates rewards to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 bobRewardsBefore = veToken.getStakingRewards(bob);
        assertEq(bobRewardsBefore, AMOUNT / Constants.REWARD_POWER_SCALAR, "Bob should have initial reward power");

        // Alice adds more stake
        vm.prank(alice);
        veToken.addToStake(AMOUNT);

        uint256 bobRewardsAfter = veToken.getStakingRewards(bob);
        assertEq(
            bobRewardsAfter, (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR, "Bob should have increased reward power"
        );
    }

    function testAddToStakeWithSplitDelegation() public {
        // Alice stakes and delegates votes to Bob, rewards to Charlie
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Add more stake
        vm.prank(alice);
        veToken.addToStake(AMOUNT);

        // Check both delegations increased
        assertEq(veToken.getVotes(bob), AMOUNT * 2, "Bob should have increased voting power");
        assertEq(
            veToken.getStakingRewards(CHARLIE),
            (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR,
            "Charlie should have increased reward power"
        );

        // Alice should have no power
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power");
        assertEq(veToken.getStakingRewards(alice), 0, "Alice should have no reward power");
    }

    function testComplexDelegationScenario() public {
        // Multiple users stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT * 2);
        vm.prank(CHARLIE);
        veToken.stake(AMOUNT * 3);

        // Initial delegations
        vm.prank(alice);
        veToken.delegate(DAVE); // Alice -> Dave (votes)
        vm.prank(alice);
        veToken.delegateRewards(DAVE); // Alice -> Dave (rewards)

        vm.prank(bob);
        veToken.delegate(DAVE); // Bob -> Dave (votes)
        vm.prank(bob);
        veToken.delegateRewards(CHARLIE); // Bob -> Charlie (rewards)

        // Check Dave's accumulated power
        assertEq(veToken.getVotes(DAVE), AMOUNT * 3, "Dave should have Alice + Bob votes");
        assertEq(
            veToken.getStakingRewards(DAVE),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Dave should have only Alice rewards"
        );

        // Check Charlie's power
        assertEq(veToken.getVotes(CHARLIE), AMOUNT * 3, "Charlie should have own votes");
        uint256 charlieExpectedRewards = (AMOUNT * 3 + AMOUNT * 2) / Constants.REWARD_POWER_SCALAR; // Own + Bob's
        assertEq(veToken.getStakingRewards(CHARLIE), charlieExpectedRewards, "Charlie should have own + Bob rewards");

        // Alice changes her mind
        vm.prank(alice);
        veToken.delegate(alice); // Take back votes
        vm.prank(alice);
        veToken.delegateRewards(bob); // Move rewards to Bob

        // Check updated distribution
        assertEq(veToken.getVotes(DAVE), AMOUNT * 2, "Dave should only have Bob's votes now");
        assertEq(veToken.getStakingRewards(DAVE), 0, "Dave should have no rewards");
        assertEq(veToken.getVotes(alice), AMOUNT, "Alice should have her votes back");
        assertEq(
            veToken.getStakingRewards(bob), AMOUNT / Constants.REWARD_POWER_SCALAR, "Bob should have Alice's rewards"
        );
    }

    function testDelegationPersistsThroughMultipleStakes() public {
        // Alice stakes initially
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice delegates
        vm.prank(alice);
        veToken.delegate(bob);
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Check initial delegation
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have voting power");
        assertEq(
            veToken.getStakingRewards(CHARLIE),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Charlie should have reward power"
        );

        // Alice adds to her stake multiple times
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            veToken.addToStake(AMOUNT);
        }

        // Delegation should persist and scale
        assertEq(veToken.getVotes(bob), AMOUNT * 4, "Bob should have 4x voting power");
        assertEq(
            veToken.getStakingRewards(CHARLIE),
            (AMOUNT * 4) / Constants.REWARD_POWER_SCALAR,
            "Charlie should have 4x reward power"
        );
    }

    function testZeroAddressDelegationBehavior() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Delegate to Bob first
        vm.prank(alice);
        veToken.delegate(bob);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have voting power");
        assertEq(veToken.getStakingRewards(bob), AMOUNT / Constants.REWARD_POWER_SCALAR, "Bob should have reward power");

        // Delegate to zero address (should be self-delegation)
        vm.prank(alice);
        veToken.delegate(address(0));
        vm.prank(alice);
        veToken.delegateRewards(address(0));

        // Should be equivalent to self-delegation
        assertEq(veToken.delegates(alice), alice, "Should delegate to self");
        assertEq(veToken.rewardDelegates(alice), alice, "Should delegate rewards to self");
        assertEq(veToken.getVotes(alice), AMOUNT, "Alice should have voting power");
        assertEq(
            veToken.getStakingRewards(alice), AMOUNT / Constants.REWARD_POWER_SCALAR, "Alice should have reward power"
        );
        assertEq(veToken.getVotes(bob), 0, "Bob should have no power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no rewards");
    }

    function testWithdrawalWithIncomingVoteDelegations() public {
        // Alice and Bob both stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT * 2);
        
        // Bob delegates votes to Alice
        vm.prank(bob);
        veToken.delegate(alice);
        
        // Check initial state: Alice has her own + Bob's voting power
        assertEq(veToken.getVotes(alice), AMOUNT * 3, "Alice should have combined voting power");
        assertEq(veToken.getVotes(bob), 0, "Bob should have no voting power");
        
        // Alice initiates unstake
        vm.prank(alice);
        veToken.initiateUnstake();
        
        // After initiating unstake:
        // - Alice's own voting power should be 0 (she's withdrawing)
        // - But she should still have Bob's delegated voting power
        assertEq(veToken.getVotes(alice), AMOUNT * 2, "Alice should only have Bob's delegated power");
        assertEq(veToken.getVotes(bob), 0, "Bob should still have no voting power");
        
        // Wait for withdrawal period
        vm.warp(block.timestamp + Constants.WITHDRAWAL_PERIOD);
        
        // Alice completes unstake
        vm.prank(alice);
        veToken.completeUnstake();
        
        // After completion:
        // - Alice should still have Bob's delegated power even without a position
        assertEq(veToken.getVotes(alice), AMOUNT * 2, "Alice should still have Bob's delegated power");
        assertEq(veToken.getVotes(bob), 0, "Bob should still have no voting power");
        
        // Bob changes delegation back to himself
        vm.prank(bob);
        veToken.delegate(bob);
        
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power");
        assertEq(veToken.getVotes(bob), AMOUNT * 2, "Bob should have his voting power back");
    }
    
    function testWithdrawalWithIncomingRewardDelegations() public {
        // Alice and Bob both stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT * 2);
        
        // Bob delegates rewards to Alice
        vm.prank(bob);
        veToken.delegateRewards(alice);
        
        // Check initial state: Alice has her own + Bob's reward power
        uint256 expectedRewardPower = (AMOUNT * 3) / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getStakingRewards(alice), expectedRewardPower, "Alice should have combined reward power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no reward power");
        
        // Alice initiates unstake
        vm.prank(alice);
        veToken.initiateUnstake();
        
        // After initiating unstake:
        // - Alice's own reward power should be 0 (she's withdrawing)
        // - But she should still have Bob's delegated reward power
        uint256 bobRewardPower = (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getStakingRewards(alice), bobRewardPower, "Alice should only have Bob's delegated reward power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should still have no reward power");
        
        // Wait for withdrawal period
        vm.warp(block.timestamp + Constants.WITHDRAWAL_PERIOD);
        
        // Alice completes unstake
        vm.prank(alice);
        veToken.completeUnstake();
        
        // After completion:
        // - Alice should still have Bob's delegated reward power
        assertEq(veToken.getStakingRewards(alice), bobRewardPower, "Alice should still have Bob's delegated reward power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should still have no reward power");
        
        // Bob changes delegation back to himself
        vm.prank(bob);
        veToken.delegateRewards(bob);
        
        assertEq(veToken.getStakingRewards(alice), 0, "Alice should have no reward power");
        assertEq(veToken.getStakingRewards(bob), bobRewardPower, "Bob should have his reward power back");
    }
    
    function testComplexDelegationChains() public {
        // Setup 5 users with stakes
        address[5] memory users = [alice, bob, CHARLIE, DAVE, address(5)];

        for (uint256 i = 0; i < users.length; i++) {
            if (i >= 4) {
                deal(address(zkc), users[i], AMOUNT * 10);
                vm.prank(users[i]);
                zkc.approve(address(veToken), type(uint256).max);
            }
            vm.prank(users[i]);
            veToken.stake(AMOUNT * (i + 1));
        }

        // Create a delegation chain
        for (uint256 i = 0; i < users.length - 1; i++) {
            vm.prank(users[i]);
            veToken.delegate(users[i + 1]);
            vm.prank(users[i]);
            veToken.delegateRewards(users[users.length - 1 - i]);
        }

        // Verify final state
        // Vote delegations form a chain: 0->1->2->3->4
        // users[4] has their own stake (5 * AMOUNT) + users[3]'s delegation (4 * AMOUNT) = 9 * AMOUNT
        assertEq(veToken.getVotes(users[4]), AMOUNT * 9, "Last user should have accumulated votes");

        // Reward delegations: users[0]->users[4], users[1]->users[3], users[2]->users[2], users[3]->users[1]
        // users[4] doesn't delegate (loop ends at i=3), so keeps their own

        // users[0] delegated their rewards to users[4], so has 0
        assertEq(veToken.getStakingRewards(users[0]), 0, "users[0] should have no rewards (delegated to users[4])");
        // users[1] receives users[3]'s delegation (4 * AMOUNT)
        assertEq(
            veToken.getStakingRewards(users[1]),
            (AMOUNT * 4) / Constants.REWARD_POWER_SCALAR,
            "users[1] should have users[3]'s rewards"
        );
        // users[2] delegates to themselves, keeps their own (3 * AMOUNT)
        assertEq(
            veToken.getStakingRewards(users[2]),
            (AMOUNT * 3) / Constants.REWARD_POWER_SCALAR,
            "users[2] should have their own rewards"
        );
        // users[3] receives users[1]'s delegation (2 * AMOUNT)
        assertEq(
            veToken.getStakingRewards(users[3]),
            (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR,
            "users[3] should have users[1]'s rewards"
        );
        // users[4] receives users[0]'s delegation (1 * AMOUNT) + keeps their own (5 * AMOUNT) = 6 * AMOUNT
        assertEq(
            veToken.getStakingRewards(users[4]),
            (AMOUNT * 6) / Constants.REWARD_POWER_SCALAR,
            "users[4] should have accumulated rewards"
        );
    }
}
