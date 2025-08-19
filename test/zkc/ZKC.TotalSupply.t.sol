// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../ZKC.t.sol";
import "../../src/libraries/Supply.sol";

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
        // Move to epoch 2 to allow minting
        vm.warp(block.timestamp + 2 * zkc.EPOCH_DURATION());
        
        uint256 mintAmount = 1000 * 10**18;
        
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, mintAmount);

        assertEq(zkc.claimedTotalSupply(), mintAmount);
        assertEq(zkc.totalSupply(), Supply.getSupplyAtEpoch(2));
    }
    
    function testTotalSupplyVsClaimedSupplyGap() public {
        // Move to epoch 5
        vm.warp(block.timestamp + 5 * zkc.EPOCH_DURATION());
        
        // Mint some rewards
        uint256 mintAmount = 1000 * 10**18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, mintAmount);
        
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
    
    function testSuppliesWithMixedMinting() public {
        // Move to epoch 3 to allow reward minting
        vm.warp(block.timestamp + 3 * zkc.EPOCH_DURATION());
        
        // Initial mint
        address[] memory recipients = new address[](1);
        recipients[0] = user;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100_000 * 10**18;
        
        vm.prank(minter1);
        zkc.initialMint(recipients, amounts);
        
        // PoVW reward mint
        uint256 povwAmount = 1000 * 10**18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, povwAmount);
        
        // Staking reward mint
        uint256 stakingAmount = 500 * 10**18;
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, stakingAmount);
        
        uint256 expectedClaimed = amounts[0] + povwAmount + stakingAmount;
        assertEq(zkc.claimedTotalSupply(), expectedClaimed);
        assertEq(zkc.totalSupply(), Supply.getSupplyAtEpoch(3));
        assertGt(zkc.totalSupply(), zkc.claimedTotalSupply());
    }

    function testClaimedSupplyTracksOnlyMintedTokens() public {
        uint256 claimedBefore = zkc.claimedTotalSupply();
        assertEq(claimedBefore, 0);
        
        // Mint some initial tokens
        address[] memory recipients = new address[](1);
        recipients[0] = user;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50_000 * 10**18;
        
        vm.prank(minter1);
        zkc.initialMint(recipients, amounts);
        assertEq(zkc.claimedTotalSupply(), amounts[0]);
        
        // Move to epoch 1 so there's allocation available for reward minting
        vm.warp(deploymentTime + zkc.EPOCH_DURATION());
        
        // Mint reward tokens
        uint256 rewardAmount = 2000 * 10**18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, rewardAmount);
        
        assertEq(zkc.claimedTotalSupply(), amounts[0] + rewardAmount);
    }

    function testTheoreticalSupplyGrowsWithTime() public {
        uint256 supplyEpoch0 = zkc.totalSupply();
        
        // Move to epoch 10
        vm.warp(deploymentTime + 10 * zkc.EPOCH_DURATION());
        uint256 supplyEpoch10 = zkc.totalSupply();
        
        // Move to epoch 100  
        vm.warp(deploymentTime + 100 * zkc.EPOCH_DURATION());
        uint256 supplyEpoch100 = zkc.totalSupply();
        
        // Theoretical supply should grow over time
        assertGt(supplyEpoch10, supplyEpoch0);
        assertGt(supplyEpoch100, supplyEpoch10);
        
        // But claimed supply should remain 0 (no minting)
        assertEq(zkc.claimedTotalSupply(), 0);
    }

    function testSupplyFunctionsDelegation() public {
        // Test that totalSupply delegates to Supply library via getSupplyAtEpochStart
        vm.warp(deploymentTime + 50 * zkc.EPOCH_DURATION());
        
        uint256 currentEpoch = zkc.getCurrentEpoch();
        assertEq(zkc.totalSupply(), Supply.getSupplyAtEpoch(currentEpoch));
        assertEq(zkc.totalSupply(), zkc.getSupplyAtEpochStart(currentEpoch));
    }
}