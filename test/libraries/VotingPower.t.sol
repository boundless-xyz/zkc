// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VotingPower} from "../../src/libraries/VotingPower.sol";
import {Checkpoints} from "../../src/libraries/Checkpoints.sol";
import {Constants} from "../../src/libraries/Constants.sol";

/**
 * @title VotingPower Library Test
 * @notice Simple unit tests for VotingPower library with withdrawal-based system
 */
contract VotingPowerTest is Test {
    using Checkpoints for Checkpoints.UserCheckpointStorage;
    using Checkpoints for Checkpoints.GlobalCheckpointStorage;
    
    Checkpoints.UserCheckpointStorage internal userStorage;
    Checkpoints.GlobalCheckpointStorage internal globalStorage;
    
    address internal alice = address(0xA11CE);
    uint256 internal constant AMOUNT = 1000 * 10**18;
    
    function setUp() public {
        // Initialize with a user point (active stake)
        userStorage.userPointHistory[alice][1] = Checkpoints.Point({
            votingAmount: AMOUNT,
            rewardAmount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: false
        });
        userStorage.userPointEpoch[alice] = 1;
        
        // Initialize global
        Checkpoints.initializeGlobalPoint(globalStorage);
        globalStorage.globalPointHistory[1] = Checkpoints.Point({
            votingAmount: AMOUNT,
            rewardAmount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: false // Global never withdraws
        });
        globalStorage.globalPointEpoch = 1;
    }
    
    function testGetVotes() public {
        uint256 votes = VotingPower.getVotes(userStorage, alice);
        assertEq(votes, AMOUNT / Constants.VOTING_POWER_SCALAR);
        
        // Voting power doesn't change over time (no decay)
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        uint256 votesLater = VotingPower.getVotes(userStorage, alice);
        assertEq(votesLater, AMOUNT / Constants.VOTING_POWER_SCALAR);
    }
    
    function testGetPastVotes() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        vm.warp(t0 + 10 weeks);
        uint256 pastVotes = VotingPower.getPastVotes(userStorage, alice, t0);
        assertEq(pastVotes, AMOUNT / Constants.VOTING_POWER_SCALAR);
    }
    
    function testGetTotalSupply() public {
        uint256 totalSupply = VotingPower.getTotalSupply(globalStorage);
        assertEq(totalSupply, AMOUNT / Constants.VOTING_POWER_SCALAR);
        
        // Total supply doesn't change over time
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        uint256 totalSupplyLater = VotingPower.getTotalSupply(globalStorage);
        assertEq(totalSupplyLater, AMOUNT / Constants.VOTING_POWER_SCALAR);
    }
    
    function testGetPastTotalSupply() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        vm.warp(t0 + 10 weeks);
        uint256 pastTotalSupply = VotingPower.getPastTotalSupply(globalStorage, t0);
        assertEq(pastTotalSupply, AMOUNT / Constants.VOTING_POWER_SCALAR);
    }
    
    function testGetVotesFromPoint() public {
        // Active point
        Checkpoints.Point memory activePoint = Checkpoints.Point({
            votingAmount: AMOUNT,
            rewardAmount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: false
        });
        
        uint256 votes = VotingPower.getVotesFromPoint(activePoint);
        assertEq(votes, AMOUNT / Constants.VOTING_POWER_SCALAR);
        
        // Withdrawing point
        Checkpoints.Point memory withdrawingPoint = Checkpoints.Point({
            votingAmount: AMOUNT,
            rewardAmount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: true
        });
        
        uint256 withdrawingVotes = VotingPower.getVotesFromPoint(withdrawingPoint);
        assertEq(withdrawingVotes, 0);
    }
    
    function testWithdrawingUserVotingPower() public {
        // Create a withdrawing user point
        userStorage.userPointHistory[alice][2] = Checkpoints.Point({
            votingAmount: AMOUNT,
            rewardAmount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: true // User is withdrawing
        });
        userStorage.userPointEpoch[alice] = 2;
        
        // Voting power should be 0 for withdrawing users
        uint256 votes = VotingPower.getVotes(userStorage, alice);
        assertEq(votes, 0);
    }
    
    function testZeroAmountVotingPower() public view {
        // Test user with no stake
        uint256 votes = VotingPower.getVotes(userStorage, address(0xBEEF));
        assertEq(votes, 0);
    }
    
    function testScalarDivision() public {
        // Test that voting power is correctly divided by scalar
        uint256 expectedVotes = AMOUNT / Constants.VOTING_POWER_SCALAR;
        uint256 actualVotes = VotingPower.getVotes(userStorage, alice);
        assertEq(actualVotes, expectedVotes);
        
        // With scalar = 1, should equal the amount
        assertEq(actualVotes, AMOUNT);
    }
}