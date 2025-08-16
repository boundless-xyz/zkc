// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ZKC.t.sol";
import "../src/libraries/Supply.sol";

contract ZKCEmissionsTest is ZKCTest {
    function setUp() public {
        deployZKC();
    }
    
    function testGetEmissionsForEpoch() public view {
        // Test basic emissions
        uint256 emission1 = zkc.getEmissionsForEpoch(1);
        uint256 emission100 = zkc.getEmissionsForEpoch(100);
        
        assertGt(emission1, 0, "Emissions should be positive");
        assertGt(emission100, 0, "Emissions should be positive");
        
        // Test delegation to Supply library
        assertEq(zkc.getEmissionsForEpoch(50), Supply.getEmissionsForEpoch(50));
    }
    
    function testGetPoVWEmissionsForEpoch() public view {
        uint256 totalEmission = zkc.getEmissionsForEpoch(1);
        uint256 povwEmission = zkc.getPoVWEmissionsForEpoch(1);
        
        // Should be 75% of total
        uint256 expected = (totalEmission * 7500) / 10000;
        assertEq(povwEmission, expected);
    }
    
    function testGetStakingEmissionsForEpoch() public view {
        uint256 totalEmission = zkc.getEmissionsForEpoch(1);
        uint256 stakingEmission = zkc.getStakingEmissionsForEpoch(1);
        
        // Should be 25% of total
        uint256 expected = (totalEmission * 2500) / 10000;
        assertEq(stakingEmission, expected);
    }
    
    function testEmissionsSumToTotal() public view {
        uint256 total = zkc.getEmissionsForEpoch(1);
        uint256 povw = zkc.getPoVWEmissionsForEpoch(1);
        uint256 staking = zkc.getStakingEmissionsForEpoch(1);
        
        assertEq(povw + staking, total);
    }
    
    function testGetPoVWRemainingForEpoch() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getPoVWEmissionsForEpoch(epoch);
        
        // Initially should equal full allocation
        assertEq(zkc.getPoVWUnclaimedForEpoch(epoch), allocation);
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        // Mint half
        uint256 mintAmount = allocation / 2;
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        // Should have half remaining
        assertEq(zkc.getPoVWUnclaimedForEpoch(epoch), allocation - mintAmount);
    }
    
    function testGetStakingRemainingForEpoch() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        // Initially should equal full allocation
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), allocation);
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        // Mint third
        uint256 mintAmount = allocation / 3;
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
        
        // Should have 2/3 remaining
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), allocation - mintAmount);
    }
    
    function testMintPoVWReward() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 mintAmount = allocation / 4;
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        // Check balance increased
        assertEq(zkc.balanceOf(user), balanceBefore + mintAmount);
        
        // Check tracking updated
        assertEq(zkc.epochPoVWMinted(epoch), mintAmount);
    }
    
    function testMintStakingReward() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getStakingEmissionsForEpoch(epoch);
        uint256 mintAmount = allocation / 4;
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
        
        // Check balance increased
        assertEq(zkc.balanceOf(user), balanceBefore + mintAmount);
        
        // Check tracking updated
        assertEq(zkc.epochStakingMinted(epoch), mintAmount);
    }
    
    function testMintRewardEvents() public {
        uint256 epoch = 1;
        uint256 mintAmount = 1000 * 10**18;
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        
        // Test PoVW event
        vm.expectEmit(true, false, false, true);
        emit ZKC.PoVWRewardsClaimed(user, amounts, epochs);
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        // Test staking event
        vm.expectEmit(true, false, false, true);
        emit ZKC.StakingRewardsClaimed(user, amounts, epochs);
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
    }
    
    function testMintRewardRevertCurrentEpoch() public {
        uint256 currentEpoch = zkc.getCurrentEpoch();
        uint256 mintAmount = 1000 * 10**18;
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, currentEpoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
    }
    
    function testMintRewardRevertExceedsAllocation() public {
        uint256 epoch = 1;
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        uint256 povwAllocation = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 stakingAllocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        (uint256[] memory povwAmounts, uint256[] memory epochs1) = _buildSingleArrayInputs(povwAllocation + 1, epoch);
        (uint256[] memory stakingAmounts, uint256[] memory epochs2) = _buildSingleArrayInputs(stakingAllocation + 1, epoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, povwAmounts, epochs1);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, stakingAmounts, epochs2);
    }
    
    function testMintRewardRevertUnauthorized() public {
        uint256 epoch = 1;
        uint256 mintAmount = 1000 * 10**18;
        
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        
        vm.expectRevert();
        vm.prank(user);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        vm.expectRevert();
        vm.prank(user);
        zkc.mintStakingRewards(user, amounts, epochs);

        vm.expectRevert();
        vm.prank(stakingMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);

        vm.expectRevert();
        vm.prank(povwMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
    }

    function testMintPoVWRewardsBatch() public {
        uint256[] memory epochs = new uint256[](3);
        epochs[0] = 1;
        epochs[1] = 2;
        epochs[2] = 3;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = zkc.getPoVWEmissionsForEpoch(1) / 4;
        amounts[1] = zkc.getPoVWEmissionsForEpoch(2) / 3;
        amounts[2] = zkc.getPoVWEmissionsForEpoch(3) / 2;
        
        // Move to epoch 4 to allow minting previous epochs
        vm.warp(deploymentTime + 4 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        uint256 expectedTotal = amounts[0] + amounts[1] + amounts[2];
        
        vm.expectEmit(true, false, false, true);
        emit ZKC.PoVWRewardsClaimed(user, amounts, epochs);
        
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        // Check balance increased by total
        assertEq(zkc.balanceOf(user), balanceBefore + expectedTotal);
        
        // Check tracking updated for each epoch
        assertEq(zkc.epochPoVWMinted(1), amounts[0]);
        assertEq(zkc.epochPoVWMinted(2), amounts[1]);
        assertEq(zkc.epochPoVWMinted(3), amounts[2]);
    }

    function testMintStakingRewardsBatch() public {
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = 1;
        epochs[1] = 2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = zkc.getStakingEmissionsForEpoch(1) / 5;
        amounts[1] = zkc.getStakingEmissionsForEpoch(2) / 6;
        
        // Move to epoch 3 to allow minting previous epochs
        vm.warp(deploymentTime + 3 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        uint256 expectedTotal = amounts[0] + amounts[1];
        
        vm.expectEmit(true, false, false, true);
        emit ZKC.StakingRewardsClaimed(user, amounts, epochs);
        
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
        
        // Check balance increased by total
        assertEq(zkc.balanceOf(user), balanceBefore + expectedTotal);
        
        // Check tracking updated for each epoch
        assertEq(zkc.epochStakingMinted(1), amounts[0]);
        assertEq(zkc.epochStakingMinted(2), amounts[1]);
    }

    function testBatchRewardsMismatchedArrayLength() public {
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = 1;
        epochs[1] = 2;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1000 * 10**18;
        amounts[1] = 2000 * 10**18;
        amounts[2] = 3000 * 10**18;
        
        vm.warp(deploymentTime + 3 * zkc.EPOCH_DURATION() + 1);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.InvalidInputLength.selector));
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.InvalidInputLength.selector));
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
    }

    function testBatchRewardsCurrentEpochReverts() public {
        vm.warp(deploymentTime + 5 * zkc.EPOCH_DURATION() + 1);
        uint256 currentEpoch = zkc.getCurrentEpoch();
        
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = currentEpoch - 1;
        epochs[1] = currentEpoch; // This should cause revert
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**18;
        amounts[1] = 2000 * 10**18;
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
    }

    function testBatchRewardsAllocationExceeded() public {
        uint256 epoch = 1;
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        uint256 povwAllocation = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 stakingAllocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = epoch;
        epochs[1] = epoch;
        
        uint256[] memory povwAmounts = new uint256[](2);
        povwAmounts[0] = povwAllocation / 2 + 1;
        povwAmounts[1] = povwAllocation / 2 + 1; // Total exceeds allocation
        
        uint256[] memory stakingAmounts = new uint256[](2);
        stakingAmounts[0] = stakingAllocation / 2 + 1;
        stakingAmounts[1] = stakingAllocation / 2 + 1; // Total exceeds allocation
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, povwAmounts, epochs);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, stakingAmounts, epochs);
    }

    function testBatchRewardsUnauthorized() public {
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 1;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**18;
        
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        // Test unauthorized user
        vm.expectRevert();
        vm.prank(user);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        vm.expectRevert();
        vm.prank(user);
        zkc.mintStakingRewards(user, amounts, epochs);
        
        // Test wrong minter role
        vm.expectRevert();
        vm.prank(stakingMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        vm.expectRevert();
        vm.prank(povwMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
    }

    function testBatchRewardsEmptyArrays() public {
        uint256[] memory epochs = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);
        
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        
        vm.prank(povwMinter);
        zkc.mintPoVWRewards(user, amounts, epochs);
        
        vm.prank(stakingMinter);
        zkc.mintStakingRewards(user, amounts, epochs);
        
        // Balance should be unchanged
        assertEq(zkc.balanceOf(user), balanceBefore);
    }
}