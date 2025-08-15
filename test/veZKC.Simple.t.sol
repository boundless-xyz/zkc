// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./veZKC.t.sol";

contract veZKCSimpleTest is veZKCTest {
    
    function testBasicStakeAndVotes() public {
        uint256 beforeVotes = veToken.getVotes(alice);
        assertEq(beforeVotes, 0);

        // Alice stakes for 30 weeks
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 30 weeks);

        (uint256 amount, uint256 expiry) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(amount, AMOUNT);
        // Expiry should be equal or rounded down to the nearest week.
        assertLe(expiry, block.timestamp + 30 weeks);
        
        // Check that getVotes works and returns some power
        uint256 votes = veToken.getVotes(alice);
        assertGt(votes, 0, "Should have some voting power");
        
        // Move forward and check decay
        vm.warp(expiry - 15 weeks);
        uint256 decayedVotes = veToken.getVotes(alice);
        assertLt(decayedVotes, votes, "Voting power should decay");

        // Check that voting power just before expiry is > 0
        vm.warp(expiry - 1);
        uint256 votesBeforeExpiry = veToken.getVotes(alice);
        assertGt(votesBeforeExpiry, 0, "Should have some voting power");
        assertLt(votesBeforeExpiry, decayedVotes, "Voting power should increase");

        // Check that voting power is 0 after expiry
        vm.warp(expiry);
        uint256 votesAfterExpiry = veToken.getVotes(alice);
        assertEq(votesAfterExpiry, 0, "Voting power should be 0 after expiry");
        
        // Check that votes don't go negative after expiry
        vm.warp(expiry + 1 weeks); // Past expiry
        uint256 expiredVotes = veToken.getVotes(alice);
        assertEq(expiredVotes, 0, "Expired votes should be 0");
    }
}