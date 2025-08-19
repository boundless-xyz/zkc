// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../ZKC.t.sol";
import "../../src/libraries/Supply.sol";

contract ZKCEpochsTest is ZKCTest {
    function setUp() public {
        deployZKC();
    }
    
    function testGetCurrentEpoch() public {
        assertEq(zkc.getCurrentEpoch(), 0);
        
        vm.warp(deploymentTime + 1 days);
        assertEq(zkc.getCurrentEpoch(), 0);
        
        vm.warp(deploymentTime + 2 days - 1 seconds);
        assertEq(zkc.getCurrentEpoch(), 0);

        vm.warp(deploymentTime + 2 days);
        assertEq(zkc.getCurrentEpoch(), 1);
        
        vm.warp(deploymentTime + 4 days);
        assertEq(zkc.getCurrentEpoch(), 2);
        
        vm.warp(deploymentTime + 365 days);
        assertEq(zkc.getCurrentEpoch(), 182);
    }
    
    function testGetEpochStartTime() public view {
        assertEq(zkc.getEpochStartTime(0), deploymentTime);
        assertEq(zkc.getEpochStartTime(1), deploymentTime + zkc.EPOCH_DURATION());
        assertEq(zkc.getEpochStartTime(10), deploymentTime + (10 * zkc.EPOCH_DURATION()));
        
        uint256 epoch = 1000;
        uint256 expectedStartTime = deploymentTime + (epoch * zkc.EPOCH_DURATION());
        assertEq(zkc.getEpochStartTime(epoch), expectedStartTime);
        assertEq(zkc.getEpochStartTime(epoch +  1), zkc.getEpochStartTime(epoch) + zkc.EPOCH_DURATION());
    }
    
    function testGetSupplyAtEpoch() public view {
        assertEq(zkc.getSupplyAtEpoch(0), zkc.INITIAL_SUPPLY());
        // Confirm delegation to Supply library        
        assertEq(zkc.getSupplyAtEpoch(100), Supply.getSupplyAtEpoch(100));
        assertEq(zkc.getSupplyAtEpoch(182), Supply.getSupplyAtEpoch(182));
        assertEq(zkc.getSupplyAtEpoch(1000), Supply.getSupplyAtEpoch(1000));
    }
    
    function testGetEmissionsForEpoch() public {
        uint256 emission0 = zkc.getEmissionsForEpoch(0);
        uint256 emission1 = zkc.getEmissionsForEpoch(1);
        uint256 emission100 = zkc.getEmissionsForEpoch(100);
        
        assertGt(emission0, 0);
        assertGt(emission1, 0);
        assertGt(emission100, 0);
        
        assertEq(zkc.getEmissionsForEpoch(50), Supply.getEmissionsForEpoch(50));
        
        uint256 total = zkc.getEmissionsForEpoch(100);
        uint256 povw = zkc.getPoVWEmissionsForEpoch(100);
        uint256 staking = zkc.getStakingEmissionsForEpoch(100);
            
        assertEq(povw + staking, total);
    }
    
    function testGetPoVWEmissionsForEpoch() public {
        uint256 totalEmission = zkc.getEmissionsForEpoch(1);
        uint256 povwEmission = zkc.getPoVWEmissionsForEpoch(1);
        
        // PoVW should get 75% of total emissions
        uint256 expectedPoVW = (totalEmission * zkc.POVW_ALLOCATION_BPS()) / zkc.BASIS_POINTS();
        assertEq(povwEmission, expectedPoVW);
    }
    
    function testGetStakingEmissionsForEpoch() public {
        uint256 totalEmission = zkc.getEmissionsForEpoch(1);
        uint256 stakingEmission = zkc.getStakingEmissionsForEpoch(1);
        
        // Staking should get 25% of total emissions
        uint256 expectedStaking = (totalEmission * zkc.STAKING_ALLOCATION_BPS()) / zkc.BASIS_POINTS();
        assertEq(stakingEmission, expectedStaking);
    }
    
    function testGetPoVWRemainingForEpoch() public {
        uint256 epoch = 1;
        uint256 totalAllocation = zkc.getPoVWEmissionsForEpoch(epoch);
        assertEq(zkc.getPoVWUnclaimedForEpoch(epoch), totalAllocation);
        
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        uint256 mintAmount = totalAllocation / 4; // Mint 25%
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);

        assertEq(zkc.balanceOf(user), mintAmount);
        assertEq(zkc.getPoVWUnclaimedForEpoch(epoch), totalAllocation - mintAmount);
        
        uint256 remainingMint = totalAllocation - mintAmount; // Mint rest
        (uint256[] memory amounts2, uint256[] memory epochs2) = _buildSingleArrayInputs(remainingMint, epoch);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts2, epochs2);
        
        assertEq(zkc.balanceOf(user), mintAmount + remainingMint);
        assertEq(zkc.getPoVWUnclaimedForEpoch(epoch), 0);
    }
    
    function testGetStakingRemainingForEpoch() public {
        uint256 epoch = 1;
        
        uint256 totalAllocation = zkc.getStakingEmissionsForEpoch(epoch);
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), totalAllocation);
        
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        uint256 mintAmount = totalAllocation / 3; // Mint 33%
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
        
        assertEq(zkc.balanceOf(user), mintAmount);
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), totalAllocation - mintAmount);

        uint256 remainingMint = totalAllocation - mintAmount; // Mint rest
        (uint256[] memory amounts2, uint256[] memory epochs2) = _buildSingleArrayInputs(remainingMint, epoch);
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts2, epochs2);
        
        assertEq(zkc.balanceOf(user), mintAmount + remainingMint);
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), 0);
    }
    
    function testMintRewardEpochValidation() public {
        uint256 currentEpoch = zkc.getCurrentEpoch();
        uint256 allocation = zkc.getPoVWEmissionsForEpoch(currentEpoch);
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(allocation / 2, currentEpoch);
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        (uint256[] memory amounts2, uint256[] memory epochs2) = _buildSingleArrayInputs(allocation / 2, currentEpoch + 1);
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch + 1));
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts2, epochs2);
        
        vm.warp(zkc.getEpochStartTime(currentEpoch + 1));
        
        (uint256[] memory amounts3, uint256[] memory epochs3) = _buildSingleArrayInputs(allocation / 2, currentEpoch);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts3, epochs3);
    }
    
    function testMintRewardAllocationLimits() public {
        uint256 epoch = zkc.getCurrentEpoch();
        
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        uint256 povwAllocation = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 stakingAllocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(povwAllocation / 2, epoch);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        (uint256[] memory amounts2, uint256[] memory epochs2) = _buildSingleArrayInputs(stakingAllocation / 2, epoch);
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts2, epochs2);
        
        (uint256[] memory amounts3, uint256[] memory epochs3) = _buildSingleArrayInputs(povwAllocation, epoch);
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts3, epochs3);
        
        (uint256[] memory amounts4, uint256[] memory epochs4) = _buildSingleArrayInputs(stakingAllocation, epoch);
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts4, epochs4);
    }
    
    function testEpochMintingEvents() public {
        uint256 epoch = 1;
        uint256 mintAmount = 1000 * 10**18;
        
        // Move to epoch 2 so we can mint for epoch 1
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        
        // Test PoVW minting event
        vm.expectEmit(true, true, false, true);
        emit ZKC.PoVWRewardsClaimed(user, epochs, amounts);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        // Test staking minting event
        vm.expectEmit(true, true, false, true);
        emit ZKC.StakingRewardsClaimed(user, epochs, amounts);
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
    }
    
}