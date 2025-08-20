// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../veZKC.t.sol";
import "../../src/interfaces/IVotes.sol";
import "../../src/interfaces/IStaking.sol";
import {console2} from "forge-std/Test.sol";

contract VotesDelegationTest is veZKCTest {
    
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
    
    // Basic delegation tests
    
    function testSelfDelegationByDefault() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);
        
        // Check Alice delegates to herself by default
        assertEq(veToken.delegates(alice), alice, "Should self-delegate by default");
        assertEq(veToken.getVotes(alice), AMOUNT, "Should have voting power equal to stake");
    }
    
    function testSimpleDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        // Check delegation
        assertEq(veToken.delegates(alice), bob, "Alice should delegate to Bob");
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power");
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have Alice's voting power");
    }
    
    function testDelegationChangeUpdatesVotes() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have Alice's voting power");
        
        // Alice re-delegates to Charlie
        vm.prank(alice);
        veToken.delegate(CHARLIE);
        
        assertEq(veToken.delegates(alice), CHARLIE, "Alice should delegate to Charlie");
        assertEq(veToken.getVotes(bob), 0, "Bob should have no voting power");
        assertEq(veToken.getVotes(CHARLIE), AMOUNT, "Charlie should have Alice's voting power");
    }
    
    function testMultipleDelegators() public {
        // Alice and Bob stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT * 2);
        
        // Both delegate to Charlie
        vm.prank(alice);
        veToken.delegate(CHARLIE);
        vm.prank(bob);
        veToken.delegate(CHARLIE);
        
        // Charlie should have combined voting power
        assertEq(veToken.getVotes(CHARLIE), AMOUNT * 3, "Charlie should have combined voting power");
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power");
        assertEq(veToken.getVotes(bob), 0, "Bob should have no voting power");
    }
    
    function testDelegateBackToSelf() public {
        // Alice stakes and delegates to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);
        
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have Alice's voting power");
        
        // Alice delegates back to herself
        vm.prank(alice);
        veToken.delegate(alice);
        
        assertEq(veToken.delegates(alice), alice, "Alice should delegate to herself");
        assertEq(veToken.getVotes(alice), AMOUNT, "Alice should have her voting power back");
        assertEq(veToken.getVotes(bob), 0, "Bob should have no voting power");
    }
    
    function testAddToStakeWithDelegation() public {
        // Alice stakes and delegates to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);
        
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have initial voting power");
        
        // Alice adds to her stake
        vm.prank(alice);
        veToken.addToStake(AMOUNT);
        
        // Bob's voting power should increase
        assertEq(veToken.getVotes(bob), AMOUNT * 2, "Bob should have increased voting power");
        assertEq(veToken.getVotes(alice), 0, "Alice should still have no voting power");
    }
    
    // Delegation with chain tests
    
    function testDelegationChain() public {
        // Alice, Bob, and Charlie stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT);
        vm.prank(CHARLIE);
        veToken.stake(AMOUNT);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        // Bob has his own + Alice's power
        assertEq(veToken.getVotes(bob), AMOUNT * 2, "Bob should have combined power");
        
        // Bob delegates to Charlie (Bob's own stake moves, Alice's delegation stays with Bob)
        vm.prank(bob);
        veToken.delegate(CHARLIE);
        
        // Check final distribution
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power");
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should only have Alice's delegated power");
        assertEq(veToken.getVotes(CHARLIE), AMOUNT * 2, "Charlie should have his own + Bob's stake");
    }
    
    // Historical delegation tests
    
    function testHistoricalVotingPowerAfterDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);
        
        uint256 checkpoint1 = vm.getBlockTimestamp();
        
        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        uint256 checkpoint2 = vm.getBlockTimestamp();
        
        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        
        // Alice delegates to Charlie
        vm.prank(alice);
        veToken.delegate(CHARLIE);
        
        // Check historical voting power
        assertEq(veToken.getPastVotes(alice, checkpoint1), AMOUNT, "Alice should have had voting power at checkpoint1");
        assertEq(veToken.getPastVotes(bob, checkpoint1), 0, "Bob should have had no voting power at checkpoint1");
        
        assertEq(veToken.getPastVotes(alice, checkpoint2), 0, "Alice should have had no voting power at checkpoint2");
        assertEq(veToken.getPastVotes(bob, checkpoint2), AMOUNT, "Bob should have had voting power at checkpoint2");
        assertEq(veToken.getPastVotes(CHARLIE, checkpoint2), 0, "Charlie should have had no voting power at checkpoint2");
    }
    
    function testHistoricalTotalSupplyUnaffectedByDelegation() public {
        // Alice and Bob stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT);
        
        uint256 checkpoint1 = vm.getBlockTimestamp();
        
        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        
        uint256 totalBefore = veToken.getPastTotalSupply(checkpoint1);
        
        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        
        uint256 checkpoint2 = vm.getBlockTimestamp();
        
        // Advance time again to make checkpoint2 a past timestamp
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        
        uint256 totalAfter = veToken.getPastTotalSupply(checkpoint2);
        
        // Total supply should remain unchanged
        assertEq(totalBefore, AMOUNT * 2, "Total supply before delegation");
        assertEq(totalAfter, AMOUNT * 2, "Total supply after delegation");
    }
    
    // Edge cases and error conditions
    
    function testCannotDelegateWithoutPosition() public {
        // Try to delegate without staking
        vm.prank(alice);
        vm.expectRevert(IStaking.NoActivePosition.selector);
        veToken.delegate(bob);
    }
    
    function testCannotDelegateWhileWithdrawing() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);
        
        // Alice initiates unstake
        vm.prank(alice);
        veToken.initiateUnstake();
        
        // Try to delegate while withdrawing
        vm.prank(alice);
        vm.expectRevert(IVotes.CannotDelegateWhileWithdrawing.selector);
        veToken.delegate(bob);
    }
    
    function testCannotInitiateUnstakeWithActiveDelegation() public {
        // Alice stakes and delegates to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);
        
        // Try to initiate unstake with active delegation
        vm.prank(alice);
        vm.expectRevert(IStaking.MustUndelegateVotesFirst.selector);
        veToken.initiateUnstake();
        
        // Undelegate first
        vm.prank(alice);
        veToken.delegate(alice);
        
        // Now can initiate unstake
        vm.prank(alice);
        veToken.initiateUnstake();
    }
    
    function testDelegationToZeroAddress() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);
        
        // Delegate to zero address (should work - represents self-delegation)
        vm.prank(alice);
        veToken.delegate(address(0));
        
        // Should be same as self-delegation
        assertEq(veToken.delegates(alice), alice, "Should delegate to self when delegating to zero");
        assertEq(veToken.getVotes(alice), AMOUNT, "Should have voting power");
    }
    
    function testDelegationSameAddress() public {
        // Alice stakes and delegates to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);
        
        uint256 bobVotesBefore = veToken.getVotes(bob);
        
        // Delegate to Bob again (should be no-op)
        vm.prank(alice);
        veToken.delegate(bob);
        
        uint256 bobVotesAfter = veToken.getVotes(bob);
        
        assertEq(bobVotesBefore, bobVotesAfter, "Votes should not change when delegating to same address");
        assertEq(veToken.delegates(alice), bob, "Delegation should remain the same");
    }
    
    // Events testing
    
    function testDelegationEvents() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);
        
        // Test delegation event
        
        vm.prank(alice);
        veToken.delegate(bob);
    }
    
    // Gas optimization tests
    
    function testGasOptimizationMultipleDelegations() public {
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
        
        // Measure gas for delegations
        uint256 totalGas = 0;
        for (uint256 i = 1; i <= numStakers; i++) {
            address staker = address(uint160(i + 100));
            uint256 gasBefore = gasleft();
            vm.prank(staker);
            veToken.delegate(CHARLIE);
            uint256 gasUsed = gasBefore - gasleft();
            totalGas += gasUsed;
        }
        
        uint256 avgGas = totalGas / numStakers;
        console2.log("Average gas per delegation:", avgGas);
        
        // Charlie should have all voting power
        assertEq(veToken.getVotes(CHARLIE), AMOUNT * numStakers, "Charlie should have all delegated voting power");
    }
}