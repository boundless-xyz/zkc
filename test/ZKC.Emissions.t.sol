// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ZKC.sol";
import "../src/libraries/Supply.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ZKCEmissionsTest is Test {
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
    
    function testGetEmissionsForEpoch() public {
        // Test basic emissions
        uint256 emission1 = zkc.getEmissionsForEpoch(1);
        uint256 emission100 = zkc.getEmissionsForEpoch(100);
        
        assertGt(emission1, 0, "Emissions should be positive");
        assertGt(emission100, 0, "Emissions should be positive");
        
        // Test delegation to Supply library
        assertEq(zkc.getEmissionsForEpoch(50), Supply.getEmissionsForEpoch(50));
    }
    
    function testGetPoVWEmissionsForEpoch() public {
        uint256 totalEmission = zkc.getEmissionsForEpoch(1);
        uint256 povwEmission = zkc.getPoVWEmissionsForEpoch(1);
        
        // Should be 75% of total
        uint256 expected = (totalEmission * 7500) / 10000;
        assertEq(povwEmission, expected);
    }
    
    function testGetStakingEmissionsForEpoch() public {
        uint256 totalEmission = zkc.getEmissionsForEpoch(1);
        uint256 stakingEmission = zkc.getStakingEmissionsForEpoch(1);
        
        // Should be 25% of total
        uint256 expected = (totalEmission * 2500) / 10000;
        assertEq(stakingEmission, expected);
    }
    
    function testEmissionsSumToTotal() public {
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
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, mintAmount, epoch);
        
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
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, mintAmount, epoch);
        
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
        
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, mintAmount, epoch);
        
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
        
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, mintAmount, epoch);
        
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
        
        // Test PoVW event
        vm.expectEmit(true, true, false, true);
        emit ZKC.PoVWRewardClaimed(epoch, user, mintAmount);
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, mintAmount, epoch);
        
        // Test staking event
        vm.expectEmit(true, true, false, true);
        emit ZKC.StakingRewardClaimed(epoch, user, mintAmount);
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, mintAmount, epoch);
    }
    
    function testMintRewardRevertCurrentEpoch() public {
        uint256 currentEpoch = zkc.getCurrentEpoch();
        uint256 mintAmount = 1000 * 10**18;
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, mintAmount, currentEpoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, mintAmount, currentEpoch);
    }
    
    function testMintRewardRevertExceedsAllocation() public {
        uint256 epoch = 1;
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        uint256 povwAllocation = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 stakingAllocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, povwAllocation + 1, epoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, stakingAllocation + 1, epoch);
    }
    
    function testMintRewardRevertUnauthorized() public {
        uint256 epoch = 1;
        uint256 mintAmount = 1000 * 10**18;
        
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        vm.expectRevert();
        vm.prank(user);
        zkc.mintPoVWReward(user, mintAmount, epoch);
        
        vm.expectRevert();
        vm.prank(user);
        zkc.mintStakingReward(user, mintAmount, epoch);

        vm.expectRevert();
        vm.prank(stakingMinter);
        zkc.mintPoVWReward(user, mintAmount, epoch);

        vm.expectRevert();
        vm.prank(povwMinter);
        zkc.mintStakingReward(user, mintAmount, epoch);
    }
}