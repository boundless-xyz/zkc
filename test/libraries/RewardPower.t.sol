// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RewardPower} from "../../src/libraries/RewardPower.sol";
import {Checkpoints} from "../../src/libraries/Checkpoints.sol";
import {Constants} from "../../src/libraries/Constants.sol";

/**
 * @title RewardPower Library Test
 * @notice Simple unit tests for RewardPower library with withdrawal-based system
 */
contract RewardPowerTest is Test {
    using Checkpoints for Checkpoints.UserCheckpointStorage;
    using Checkpoints for Checkpoints.GlobalCheckpointStorage;
    
    Checkpoints.UserCheckpointStorage internal userStorage;
    Checkpoints.GlobalCheckpointStorage internal globalStorage;
    
    address internal alice = address(0xA11CE);
    uint256 internal constant AMOUNT = 1000 * 10**18;
    
    function setUp() public {
        // Initialize with a user point (active stake)
        userStorage.userPointHistory[alice][1] = Checkpoints.Point({
            amount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: false
        });
        userStorage.userPointEpoch[alice] = 1;
        
        // Initialize global
        Checkpoints.initializeGlobalPoint(globalStorage);
        globalStorage.globalPointHistory[1] = Checkpoints.Point({
            amount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: false // Global never withdraws
        });
        globalStorage.globalPointEpoch = 1;
    }
    
    function testGetRewards() public {
        uint256 rewards = RewardPower.getStakingRewards(userStorage, alice);
        assertEq(rewards, AMOUNT / Constants.REWARD_POWER_SCALAR);
        
        // Reward power doesn't change over time (no decay)
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        uint256 rewardsLater = RewardPower.getStakingRewards(userStorage, alice);
        assertEq(rewardsLater, AMOUNT / Constants.REWARD_POWER_SCALAR);
    }
    
    function testGetPastRewards() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        vm.warp(t0 + 10 weeks);
        uint256 pastRewards = RewardPower.getPastStakingRewards(userStorage, alice, t0);
        assertEq(pastRewards, AMOUNT / Constants.REWARD_POWER_SCALAR);
    }
    
    function testGetTotalRewards() public {
        uint256 totalRewards = RewardPower.getTotalStakingRewards(globalStorage);
        assertEq(totalRewards, AMOUNT / Constants.REWARD_POWER_SCALAR);
        
        // Total rewards don't change over time
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        uint256 totalRewardsLater = RewardPower.getTotalStakingRewards(globalStorage);
        assertEq(totalRewardsLater, AMOUNT / Constants.REWARD_POWER_SCALAR);
    }
    
    function testGetPastTotalRewards() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        vm.warp(t0 + 10 weeks);
        uint256 pastTotalRewards = RewardPower.getPastTotalStakingRewards(globalStorage, t0);
        assertEq(pastTotalRewards, AMOUNT / Constants.REWARD_POWER_SCALAR);
    }
    
    function testWithdrawingUserRewardPower() public {
        // Create a withdrawing user point
        userStorage.userPointHistory[alice][2] = Checkpoints.Point({
            amount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: true // User is withdrawing
        });
        userStorage.userPointEpoch[alice] = 2;
        
        // Reward power should be 0 for withdrawing users
        uint256 rewards = RewardPower.getStakingRewards(userStorage, alice);
        assertEq(rewards, 0);
    }
    
    function testZeroAmountRewardPower() public view {
        // Test user with no stake
        uint256 rewards = RewardPower.getStakingRewards(userStorage, address(0xBEEF));
        assertEq(rewards, 0);
    }
    
    function testScalarDivision() public {
        // Test that reward power is correctly divided by scalar
        uint256 expectedRewards = AMOUNT / Constants.REWARD_POWER_SCALAR;
        uint256 actualRewards = RewardPower.getStakingRewards(userStorage, alice);
        assertEq(actualRewards, expectedRewards);
        
        // With scalar = 1, should equal the amount
        assertEq(actualRewards, AMOUNT);
    }
}