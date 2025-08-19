// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VotingPower} from "../../src/libraries/VotingPower.sol";
import {Checkpoints} from "../../src/libraries/Checkpoints.sol";
import {Constants} from "../../src/libraries/Constants.sol";

/**
 * @title VotingPower Library Test
 * @notice Simple unit tests for VotingPower library
 */
contract VotingPowerTest is Test {
    using Checkpoints for Checkpoints.UserCheckpointStorage;
    using Checkpoints for Checkpoints.GlobalCheckpointStorage;
    
    Checkpoints.UserCheckpointStorage internal userStorage;
    Checkpoints.GlobalCheckpointStorage internal globalStorage;
    
    address internal alice = address(0xA11CE);
    uint256 internal constant AMOUNT = 1000 * 10**18;
    
    function setUp() public {
        // Initialize with a user point
        userStorage.userPointHistory[alice][1] = Checkpoints.Point({
            bias: int128(int256(AMOUNT)),
            slope: int128(int256(AMOUNT / Constants.MAX_STAKE_TIME_S)),
            updatedAt: vm.getBlockTimestamp(),
            amount: AMOUNT
        });
        userStorage.userPointEpoch[alice] = 1;
        
        // Initialize global
        Checkpoints.initializeGlobalPoint(globalStorage);
        globalStorage.globalPointHistory[1] = Checkpoints.Point({
            bias: int128(int256(AMOUNT)),
            slope: int128(int256(AMOUNT / Constants.MAX_STAKE_TIME_S)),
            updatedAt: vm.getBlockTimestamp(),
            amount: AMOUNT
        });
        globalStorage.globalPointEpoch = 1;
    }
    
    function testGetVotes() public {
        uint256 votes = VotingPower.getVotes(userStorage, alice);
        assertApproxEqRel(votes, AMOUNT, 0.01e18);
        
        // Advance time and check decay
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        uint256 votesLater = VotingPower.getVotes(userStorage, alice);
        assertLt(votesLater, votes);
        assertApproxEqRel(votesLater, AMOUNT / 2, 0.02e18);
    }
    
    function testGetPastVotes() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        vm.warp(t0 + 10 weeks);
        uint256 pastVotes = VotingPower.getPastVotes(userStorage, alice, t0);
        assertApproxEqRel(pastVotes, AMOUNT, 0.01e18);
        
        // Check votes decay over time
        uint256 pastVotesLater = VotingPower.getPastVotes(userStorage, alice, t0 + 5 weeks);
        assertLt(pastVotesLater, pastVotes);
    }
    
    function testGetPastTotalSupply() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        vm.warp(t0 + 10 weeks);
        uint256 totalSupply = VotingPower.getPastTotalSupply(globalStorage, t0);
        assertApproxEqRel(totalSupply, AMOUNT, 0.01e18, "Total supply should be the initial amount");
        
        // Check decay
        uint256 totalSupplyLater = VotingPower.getPastTotalSupply(globalStorage, t0 + 5 weeks);
        assertLt(totalSupplyLater, totalSupply, "Total supply should decay over time");
    }
    
    function testZeroVotingPower() public {
        // Test user with no points
        address bob = address(0xB0B);
        uint256 votes = VotingPower.getVotes(userStorage, bob);
        assertEq(votes, 0);
        
        // Test after expiry
        vm.warp(vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S + 1);
        uint256 expiredVotes = VotingPower.getVotes(userStorage, alice);
        assertEq(expiredVotes, 0);
    }
    
    // =============================================================
    //          TESTS MOVED FROM CHECKPOINTS.T.SOL
    // =============================================================
    
    function testGetVotesFromEpoch() public {
        // Create a point with bias and slope
        int128 slope = int128(int256(1000e18)) / Constants.iMAX_STAKE_TIME_S;
        Checkpoints.Point memory point = Checkpoints.Point({
            bias: 1000e18, // 1000 tokens worth of bias
            slope: slope, // slope per second (1000e18 / MAX_STAKE_TIME_S)
            updatedAt: vm.getBlockTimestamp(),
            amount: 1000e18
        });
        
        // Voting power should equal bias at creation time
        uint256 votesAtCreation = VotingPower.getVotesFromEpoch(point, vm.getBlockTimestamp());
        assertEq(votesAtCreation, 1000e18, "Votes at creation should equal bias");
        
        // After 1 week, voting power should decay
        uint256 votesAfter1Week = VotingPower.getVotesFromEpoch(point, vm.getBlockTimestamp() + 1 weeks);
        assertLt(votesAfter1Week, 1000e18, "Votes should decay over time");
        
        // After MAX_STAKE_TIME_S, voting power should be 0
        uint256 votesAfterMax = VotingPower.getVotesFromEpoch(point, vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S + 1);
        assertEq(votesAfterMax, 0, "Votes should be 0 after max time");
        
        // Verify linear decay calculation
        uint256 expectedAfter1Week = 1000e18 - (uint256(int256(slope)) * 1 weeks);
        assertApproxEqAbs(votesAfter1Week, expectedAfter1Week, 1e6, "Linear decay should be accurate");
    }
    
    function testGetVotesFromEpochEmptyPoint() public {
        Checkpoints.Point memory emptyPoint;
        uint256 votes = VotingPower.getVotesFromEpoch(emptyPoint, vm.getBlockTimestamp());
        assertEq(votes, 0, "Empty point should have 0 votes");
    }
    
    function testGetVotesFromEpochNeverNegative() public {
        int128 slope = int128(int256(100e18)) / Constants.iMAX_STAKE_TIME_S;
        Checkpoints.Point memory point = Checkpoints.Point({
            bias: 100e18,
            slope: slope,
            updatedAt: vm.getBlockTimestamp(),
            amount: 1000e18
        });
        
        // Query way in the future when bias would be negative
        uint256 futureTimestamp = vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S * 2;
        uint256 votes = VotingPower.getVotesFromEpoch(point, futureTimestamp);
        assertEq(votes, 0, "Votes should never be negative");
    }
    
    function testGetPastTotalSupplyEmpty() public {
        // Test with a fresh storage that has epoch = 0 (no checkpoints)
        Checkpoints.GlobalCheckpointStorage storage emptyStorage = globalStorage;
        // Save current epoch and reset it
        uint256 savedEpoch = globalStorage.globalPointEpoch;
        globalStorage.globalPointEpoch = 0;
        
        uint256 totalSupply = VotingPower.getPastTotalSupply(emptyStorage, vm.getBlockTimestamp());
        assertEq(totalSupply, 0, "Empty global history should return 0");
        
        // Restore epoch
        globalStorage.globalPointEpoch = savedEpoch;
    }
    
    function testGetPastTotalSupplySimple() public {
        // Add a global point
        uint256 testTime = vm.getBlockTimestamp();
        globalStorage.globalPointHistory[1] = Checkpoints.Point({
            bias: 1000e18,
            slope: 48116,
            updatedAt: testTime,
            amount: 1000e18
        });
        globalStorage.globalPointEpoch = 1;
        
        // Test getting past total supply
        vm.warp(testTime + 1 weeks);
        uint256 totalSupply = VotingPower.getPastTotalSupply(globalStorage, testTime + 3600);
        assertGt(totalSupply, 0, "Should have positive total supply");
        assertLt(totalSupply, 1000e18, "Should decay from initial bias");
    }
    
    function testGetPastTotalSupplyWithSlopeChanges() public {
        uint256 testTime = Checkpoints.timestampFloorToWeek(vm.getBlockTimestamp());
        uint256 weekAfter = testTime + 1 weeks;
        
        // Add a global point
        globalStorage.globalPointHistory[1] = Checkpoints.Point({
            bias: 1000e18,
            slope: 48116,
            updatedAt: testTime,
            amount: 1000e18
        });
        globalStorage.globalPointEpoch = 1;
        
        // Add a slope change at the week boundary
        globalStorage.slopeChanges[weekAfter] = -24058; // Half the slope
        
        vm.warp(weekAfter + 1);
        uint256 totalSupply = VotingPower.getPastTotalSupply(globalStorage, weekAfter + 3600);
        assertGt(totalSupply, 0, "Should have positive total supply after slope change");
    }
}