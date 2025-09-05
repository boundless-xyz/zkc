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
    uint256 internal constant AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        // Initialize with a user point (active stake)
        userStorage.userPointHistory[alice][1] = Checkpoints.Point({
            votingAmount: AMOUNT,
            rewardAmount: AMOUNT,
            updatedAt: vm.getBlockTimestamp()
        });
        userStorage.userPointEpoch[alice] = 1;

        // Initialize global
        Checkpoints.initializeGlobalPoint(globalStorage);
        globalStorage.globalPointHistory[1] = Checkpoints.Point({
            votingAmount: AMOUNT,
            rewardAmount: AMOUNT,
            updatedAt: vm.getBlockTimestamp()
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
            updatedAt: vm.getBlockTimestamp()
        });

        uint256 votes = VotingPower.getVotesFromPoint(activePoint);
        assertEq(votes, AMOUNT / Constants.VOTING_POWER_SCALAR);
        
        // Zero point (user has withdrawn)
        Checkpoints.Point memory zeroPoint = Checkpoints.Point({
            votingAmount: 0,
            rewardAmount: 0,
            updatedAt: vm.getBlockTimestamp()
        });

        uint256 zeroVotes = VotingPower.getVotesFromPoint(zeroPoint);
        assertEq(zeroVotes, 0);
    }

    function testZeroVotingPowerAfterWithdrawal() public {
        // Create a point with zero amounts (user has withdrawn)
        userStorage.userPointHistory[alice][2] = Checkpoints.Point({
            votingAmount: 0,
            rewardAmount: 0,
            updatedAt: vm.getBlockTimestamp()
        });
        userStorage.userPointEpoch[alice] = 2;

        // Voting power should be 0 after withdrawal
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
