// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RewardPower} from "../../src/libraries/RewardPower.sol";
import {Checkpoints} from "../../src/libraries/Checkpoints.sol";
import {Constants} from "../../src/libraries/Constants.sol";

/**
 * @title RewardPower Library Test
 * @notice Simple unit tests for RewardPower library
 */
contract RewardPowerTest is Test {
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
            updatedAt: block.timestamp,
            amount: AMOUNT
        });
        userStorage.userPointEpoch[alice] = 1;
        
        // Initialize global
        Checkpoints.initializeGlobalPoint(globalStorage);
        globalStorage.globalPointHistory[1] = Checkpoints.Point({
            bias: int128(int256(AMOUNT)),
            slope: int128(int256(AMOUNT / Constants.MAX_STAKE_TIME_S)),
            updatedAt: block.timestamp,
            amount: AMOUNT
        });
        globalStorage.globalPointEpoch = 1;
    }
    
    function testGetRewards() public {
        uint256 rewards = RewardPower.getRewards(userStorage, alice);
        assertEq(rewards, AMOUNT);
        
        // Reward power doesn't decay over time
        vm.warp(block.timestamp + 52 weeks);
        uint256 rewardsLater = RewardPower.getRewards(userStorage, alice);
        assertEq(rewardsLater, AMOUNT);
    }
    
    function testGetPastRewards() public {
        uint256 t0 = block.timestamp;
        
        vm.warp(t0 + 10 weeks);
        uint256 pastRewards = RewardPower.getPastRewards(userStorage, alice, t0);
        assertEq(pastRewards, AMOUNT);
    }
    
    function testGetTotalRewards() public {
        uint256 totalRewards = RewardPower.getTotalRewards(globalStorage);
        assertEq(totalRewards, AMOUNT);
        
        // Total rewards don't decay
        vm.warp(block.timestamp + 52 weeks);
        uint256 totalRewardsLater = RewardPower.getTotalRewards(globalStorage);
        assertEq(totalRewardsLater, AMOUNT);
    }
    
    function testGetPastTotalRewards() public {
        uint256 t0 = block.timestamp;
        
        vm.warp(t0 + 10 weeks);
        uint256 pastTotalRewards = RewardPower.getPastTotalRewards(globalStorage, t0);
        assertEq(pastTotalRewards, AMOUNT);
    }
    
    function testExpiredLockRewardPower() public {
        // Create an expired lock point
        userStorage.userPointHistory[alice][2] = Checkpoints.Point({
            bias: 0, // Expired, no bias
            slope: 0, // Expired, no slope
            updatedAt: block.timestamp + Constants.MAX_STAKE_TIME_S,
            amount: AMOUNT // Amount persists
        });
        userStorage.userPointEpoch[alice] = 2;
        
        vm.warp(block.timestamp + Constants.MAX_STAKE_TIME_S + 1);
        
        // Reward power persists even after expiry
        uint256 rewards = RewardPower.getRewards(userStorage, alice);
        assertEq(rewards, AMOUNT);
    }
}