// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RewardPower} from "../../src/libraries/RewardPower.sol";
import {Checkpoints} from "../../src/libraries/Checkpoints.sol";
import {Constants} from "../../src/libraries/Constants.sol";

/**
 * @title RewardPower Library Test
 * @notice Comprehensive unit tests for RewardPower library with both staking rewards and PoVW reward cap
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
    
    function testGetStakingRewards() public {
        uint256 rewards = RewardPower.getStakingRewards(userStorage, alice);
        assertEq(rewards, AMOUNT / Constants.REWARD_POWER_SCALAR);
        
        // Reward power doesn't change over time (no decay)
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        uint256 rewardsLater = RewardPower.getStakingRewards(userStorage, alice);
        assertEq(rewardsLater, AMOUNT / Constants.REWARD_POWER_SCALAR);
    }
    
    function testGetPastStakingRewards() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        vm.warp(t0 + 10 weeks);
        uint256 pastRewards = RewardPower.getPastStakingRewards(userStorage, alice, t0);
        assertEq(pastRewards, AMOUNT / Constants.REWARD_POWER_SCALAR);
    }
    
    function testGetTotalStakingRewards() public {
        uint256 totalRewards = RewardPower.getTotalStakingRewards(globalStorage);
        assertEq(totalRewards, AMOUNT / Constants.REWARD_POWER_SCALAR);
        
        // Total rewards don't change over time
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        uint256 totalRewardsLater = RewardPower.getTotalStakingRewards(globalStorage);
        assertEq(totalRewardsLater, AMOUNT / Constants.REWARD_POWER_SCALAR);
    }
    
    function testGetPastTotalStakingRewards() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        vm.warp(t0 + 10 weeks);
        uint256 pastTotalRewards = RewardPower.getPastTotalStakingRewards(globalStorage, t0);
        assertEq(pastTotalRewards, AMOUNT / Constants.REWARD_POWER_SCALAR);
    }
    
    function testWithdrawingUserStakingRewards() public {
        // Create a withdrawing user point
        userStorage.userPointHistory[alice][2] = Checkpoints.Point({
            amount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: true // User is withdrawing
        });
        userStorage.userPointEpoch[alice] = 2;
        
        // Staking rewards should be 0 for withdrawing users
        uint256 rewards = RewardPower.getStakingRewards(userStorage, alice);
        assertEq(rewards, 0);
    }
    
    function testZeroAmountStakingRewards() public view {
        // Test user with no stake
        uint256 rewards = RewardPower.getStakingRewards(userStorage, address(0xBEEF));
        assertEq(rewards, 0);
    }
    
    function testStakingRewardsScalarDivision() public {
        // Test that staking rewards are correctly divided by REWARD_POWER_SCALAR
        uint256 expectedRewards = AMOUNT / Constants.REWARD_POWER_SCALAR;
        uint256 actualRewards = RewardPower.getStakingRewards(userStorage, alice);
        assertEq(actualRewards, expectedRewards);
        
        // With scalar = 1, should equal the amount
        assertEq(actualRewards, AMOUNT);
    }
    
    // ============ PoVW Reward Cap Tests ============
    
    function testGetPoVWRewardCap() public {
        uint256 cap = RewardPower.getPoVWRewardCap(userStorage, alice);
        assertEq(cap, AMOUNT / Constants.POVW_REWARD_CAP_SCALAR);
        
        // Cap doesn't change over time (no decay)
        vm.warp(vm.getBlockTimestamp() + 52 weeks);
        uint256 capLater = RewardPower.getPoVWRewardCap(userStorage, alice);
        assertEq(capLater, AMOUNT / Constants.POVW_REWARD_CAP_SCALAR);
    }
    
    function testGetPastPoVWRewardCap() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        vm.warp(t0 + 10 weeks);
        uint256 pastCap = RewardPower.getPastPoVWRewardCap(userStorage, alice, t0);
        assertEq(pastCap, AMOUNT / Constants.POVW_REWARD_CAP_SCALAR);
    }
    
    function testWithdrawingUserPoVWRewardCap() public {
        // Create a withdrawing user point
        userStorage.userPointHistory[alice][2] = Checkpoints.Point({
            amount: AMOUNT,
            updatedAt: vm.getBlockTimestamp(),
            withdrawing: true // User is withdrawing
        });
        userStorage.userPointEpoch[alice] = 2;
        
        // PoVW reward cap should be 0 for withdrawing users
        uint256 cap = RewardPower.getPoVWRewardCap(userStorage, alice);
        assertEq(cap, 0);
    }
    
    function testZeroAmountPoVWRewardCap() public view {
        // Test user with no stake
        uint256 cap = RewardPower.getPoVWRewardCap(userStorage, address(0xBEEF));
        assertEq(cap, 0);
    }
    
    function testPoVWRewardCapScalarDivision() public {
        // Test that PoVW reward cap is correctly divided by POVW_REWARD_CAP_SCALAR
        uint256 expectedCap = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        uint256 actualCap = RewardPower.getPoVWRewardCap(userStorage, alice);
        assertEq(actualCap, expectedCap, "PoVW cap should equal amount divided by POVW_REWARD_CAP_SCALAR");
    }
    
    function testCompareStakingRewardsVsPoVWCap() public {
        // Compare staking rewards vs PoVW cap for same user
        uint256 stakingRewards = RewardPower.getStakingRewards(userStorage, alice);
        uint256 povwCap = RewardPower.getPoVWRewardCap(userStorage, alice);
        
        // Verify both values are correctly scaled
        assertEq(stakingRewards, AMOUNT / Constants.REWARD_POWER_SCALAR, "Staking rewards should equal amount divided by REWARD_POWER_SCALAR");
        assertEq(povwCap, AMOUNT / Constants.POVW_REWARD_CAP_SCALAR, "PoVW cap should equal amount divided by POVW_REWARD_CAP_SCALAR");
        
        // The relationship between staking rewards and PoVW cap is determined by the scalars
        // Account for rounding error from integer division
        uint256 expectedMultiplier = Constants.POVW_REWARD_CAP_SCALAR / Constants.REWARD_POWER_SCALAR;
        assertApproxEqAbs(stakingRewards, povwCap * expectedMultiplier, 1,
            "Staking rewards should be POVW_REWARD_CAP_SCALAR/REWARD_POWER_SCALAR times the PoVW cap");
    }
    
    function testHistoricalConsistency() public {
        uint256 t0 = vm.getBlockTimestamp();
        
        // Record initial values
        uint256 initialStakingRewards = RewardPower.getStakingRewards(userStorage, alice);
        uint256 initialPoVWCap = RewardPower.getPoVWRewardCap(userStorage, alice);
        
        // Move forward in time
        vm.warp(t0 + 20 weeks);
        
        // Query historical values
        uint256 pastStakingRewards = RewardPower.getPastStakingRewards(userStorage, alice, t0);
        uint256 pastPoVWCap = RewardPower.getPastPoVWRewardCap(userStorage, alice, t0);
        
        // Historical values should match initial values
        assertEq(pastStakingRewards, initialStakingRewards);
        assertEq(pastPoVWCap, initialPoVWCap);
        
        // Current values should also be the same (no decay)
        assertEq(RewardPower.getStakingRewards(userStorage, alice), initialStakingRewards);
        assertEq(RewardPower.getPoVWRewardCap(userStorage, alice), initialPoVWCap);
    }
}