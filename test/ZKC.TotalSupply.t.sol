// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ZKC.t.sol";
import "../src/libraries/Supply.sol";

contract ZKCTotalSupplyTest is ZKCTest {
    function setUp() public {
        deployZKC();
    }
    
    function testInitialTotalSupply() public {
        // Both should start at initial supply
        assertEq(zkc.totalSupply(), zkc.INITIAL_SUPPLY());
        assertEq(zkc.claimedTotalSupply(), 0);
    }
    
    function testTotalSupplyIncreasesWithEpochs() public {
        // Move to epoch 1
        vm.warp(block.timestamp + zkc.EPOCH_DURATION());
        
        uint256 expectedSupply = Supply.getSupplyAtEpoch(1);
        assertEq(zkc.totalSupply(), expectedSupply);
        
        // Move to epoch 10
        vm.warp(block.timestamp + 9 * zkc.EPOCH_DURATION());
        
        expectedSupply = Supply.getSupplyAtEpoch(10);
        assertEq(zkc.totalSupply(), expectedSupply);
    }
    
    function testClaimedTotalSupplyAfterInitialMint() public {
        // Initial minter 1 mints half
        address[] memory recipients = new address[](1);
        recipients[0] = user;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = zkc.INITIAL_SUPPLY() / 2;
        
        vm.prank(minter1);
        zkc.initialMint(recipients, amounts);
        
        assertEq(zkc.claimedTotalSupply(), zkc.INITIAL_SUPPLY() / 2);
        assertEq(zkc.totalSupply(), zkc.INITIAL_SUPPLY());
    }
    
    function testClaimedTotalSupplyAfterRewardMint() public {
        // Move to epoch 2 to mint rewards for epoch 1
        vm.warp(block.timestamp + 2 * zkc.EPOCH_DURATION());
        
        uint256 mintAmount = 1000 * 10**18;
        
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, mintAmount, 1);
        
        assertEq(zkc.claimedTotalSupply(), mintAmount);
        assertEq(zkc.totalSupply(), Supply.getSupplyAtEpoch(2));
    }
    
    function testTotalSupplyVsClaimedSupplyGap() public {
        // Move to epoch 5
        vm.warp(block.timestamp + 5 * zkc.EPOCH_DURATION());
        
        // Mint some rewards for epoch 1
        uint256 mintAmount = 1000 * 10**18;
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, mintAmount, 1);
        
        // totalSupply should be much higher than claimed
        uint256 theoretical = zkc.totalSupply();
        uint256 claimed = zkc.claimedTotalSupply();
        
        assertGt(theoretical, claimed);
        assertEq(theoretical, Supply.getSupplyAtEpoch(5));
        assertEq(claimed, mintAmount);
    }
    
    function testBothSuppliesAfterFullInitialMint() public {
        // Mint all initial supply
        address[] memory recipients1 = new address[](1);
        recipients1[0] = user;
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = zkc.INITIAL_SUPPLY() / 2;
        
        vm.prank(minter1);
        zkc.initialMint(recipients1, amounts1);
        
        address[] memory recipients2 = new address[](1);
        recipients2[0] = user;
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = zkc.INITIAL_SUPPLY() / 2;
        
        vm.prank(minter2);
        zkc.initialMint(recipients2, amounts2);
        
        // At epoch 0, both should equal initial supply
        assertEq(zkc.claimedTotalSupply(), zkc.INITIAL_SUPPLY());
        assertEq(zkc.totalSupply(), zkc.INITIAL_SUPPLY());
        
        // Move to epoch 1
        vm.warp(block.timestamp + zkc.EPOCH_DURATION());
        
        // Now theoretical should be higher
        assertEq(zkc.claimedTotalSupply(), zkc.INITIAL_SUPPLY());
        assertGt(zkc.totalSupply(), zkc.INITIAL_SUPPLY());
    }
    
    function testSuppliesWithPartialEpochClaims() public {
        // Move to epoch 3
        vm.warp(block.timestamp + 3 * zkc.EPOCH_DURATION());
        
        // Mint partial rewards for epoch 1
        uint256 epoch1Emissions = zkc.getPoVWEmissionsForEpoch(1);
        vm.prank(povwMinter);
        zkc.mintPoVWReward(user, epoch1Emissions / 2, 1);
        
        // Mint full rewards for epoch 2 staking
        uint256 epoch2StakingEmissions = zkc.getStakingEmissionsForEpoch(2);
        vm.prank(stakingMinter);
        zkc.mintStakingReward(user, epoch2StakingEmissions, 2);
        
        uint256 totalMinted = epoch1Emissions / 2 + epoch2StakingEmissions;
        
        assertEq(zkc.claimedTotalSupply(), totalMinted);
        assertEq(zkc.totalSupply(), Supply.getSupplyAtEpoch(3));
        assertGt(zkc.totalSupply(), zkc.claimedTotalSupply());
    }
}