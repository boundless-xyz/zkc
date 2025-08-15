// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ZKC.sol";
import "../src/libraries/Supply.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ZKCEpochsTest is Test {
    ZKC public zkc;
    ZKC public implementation;
    
    address public owner = makeAddr("owner");
    address public minter1 = makeAddr("minter1");
    address public minter2 = makeAddr("minter2");
    address public povwMinter = makeAddr("povwMinter");
    address public stakingMinter = makeAddr("stakingMinter");
    address public user = makeAddr("user");
    
    uint256 public deploymentTime;
    
    function setUp() public {
        // Deploy implementation
        implementation = new ZKC();
        
        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            ZKC.initialize.selector,
            minter1,
            minter2,
            implementation.INITIAL_SUPPLY() / 2,
            implementation.INITIAL_SUPPLY() / 2,
            owner
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        zkc = ZKC(address(proxy));
        
        // Initialize V2 to set deployment time
        vm.prank(owner);
        zkc.initializeV2();
        deploymentTime = block.timestamp;
        
        // Grant roles
        vm.startPrank(owner);
        zkc.grantRole(zkc.POVW_MINTER_ROLE(), povwMinter);
        zkc.grantRole(zkc.STAKING_MINTER_ROLE(), stakingMinter);
        vm.stopPrank();
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
    
    function testGetEmissionsForEpoch() public view {
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
    
    function testGetPoVWEmissionsForEpoch() public view {
        uint256 totalEmission = zkc.getEmissionsForEpoch(1);
        uint256 povwEmission = zkc.getPoVWEmissionsForEpoch(1);
        
        // PoVW should get 75% of total emissions
        uint256 expectedPoVW = (totalEmission * zkc.POVW_ALLOCATION_BPS()) / zkc.BASIS_POINTS();
        assertEq(povwEmission, expectedPoVW);
    }
    
    function testGetStakingEmissionsForEpoch() public view {
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
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, mintAmount, epoch);

        assertEq(zkc.balanceOf(user), mintAmount);
        assertEq(zkc.getPoVWUnclaimedForEpoch(epoch), totalAllocation - mintAmount);
        
        uint256 remainingMint = totalAllocation - mintAmount; // Mint rest
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, remainingMint, epoch);
        
        assertEq(zkc.balanceOf(user), mintAmount + remainingMint);
        assertEq(zkc.getPoVWUnclaimedForEpoch(epoch), 0);
    }
    
    function testGetStakingRemainingForEpoch() public {
        uint256 epoch = 1;
        
        uint256 totalAllocation = zkc.getStakingEmissionsForEpoch(epoch);
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), totalAllocation);
        
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        uint256 mintAmount = totalAllocation / 3; // Mint 33%
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, mintAmount, epoch);
        
        assertEq(zkc.balanceOf(user), mintAmount);
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), totalAllocation - mintAmount);

        uint256 remainingMint = totalAllocation - mintAmount; // Mint rest
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, remainingMint, epoch);
        
        assertEq(zkc.balanceOf(user), mintAmount + remainingMint);
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), 0);
    }
    
    function testMintRewardEpochValidation() public {
        uint256 currentEpoch = zkc.getCurrentEpoch();
        uint256 allocation = zkc.getPoVWEmissionsForEpoch(currentEpoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, allocation / 2, currentEpoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch + 1));
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, allocation / 2, currentEpoch + 1);
        
        vm.warp(zkc.getEpochStartTime(currentEpoch + 1));
        
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, allocation / 2, currentEpoch);
    }
    
    function testMintRewardAllocationLimits() public {
        uint256 epoch = zkc.getCurrentEpoch();
        
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        uint256 povwAllocation = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 stakingAllocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, povwAllocation / 2, epoch);
        
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, stakingAllocation / 2, epoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, povwAllocation, epoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, stakingAllocation, epoch);
    }
    
    function testEpochMintingEvents() public {
        uint256 epoch = 1;
        uint256 mintAmount = 1000 * 10**18;
        
        // Move to epoch 2 so we can mint for epoch 1
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        // Test PoVW minting event
        vm.expectEmit(true, true, false, true);
        emit ZKC.PoVWRewardClaimed(epoch, user, mintAmount);
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, mintAmount, epoch);
        
        // Test staking minting event
        vm.expectEmit(true, true, false, true);
        emit ZKC.StakingRewardClaimed(epoch, user, mintAmount);
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, mintAmount, epoch);
    }
    
}