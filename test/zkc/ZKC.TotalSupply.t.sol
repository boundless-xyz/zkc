// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../ZKC.t.sol";
import "../../src/libraries/Supply.sol";

contract ZKCTotalSupplyTest is ZKCTest {
    function setUp() public {
        deployZKC();

        // Perform the initial mints
        address[] memory recipients = new address[](1);
        recipients[0] = user;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = zkc.INITIAL_SUPPLY() / 2;        
        vm.prank(minter1);
        zkc.initialMint(recipients, amounts);
        address[] memory recipients2 = new address[](1);
        recipients2[0] = user;
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = zkc.INITIAL_SUPPLY() / 2;        
        vm.prank(minter2);
        zkc.initialMint(recipients2, amounts2);
    }

    function testInitialTotalSupply() public view {
        assertEq(zkc.totalSupply(), zkc.INITIAL_SUPPLY());
        assertEq(zkc.claimedTotalSupply(), zkc.INITIAL_SUPPLY());
    }

    function testTotalSupplyIncreasesWithEpochs() public {
        // Move to epoch 1
        vm.warp(vm.getBlockTimestamp() + zkc.EPOCH_DURATION());

        uint256 expectedSupply = Supply.getSupplyAtEpoch(1);
        assertEq(zkc.totalSupply(), expectedSupply);

        // Move to epoch 10
        vm.warp(vm.getBlockTimestamp() + 9 * zkc.EPOCH_DURATION());

        expectedSupply = Supply.getSupplyAtEpoch(10);
        assertEq(zkc.totalSupply(), expectedSupply);
    }

    function testClaimedTotalSupplyAfterRewardMint() public {
        // Move to epoch 2 to allow minting
        vm.warp(vm.getBlockTimestamp() + 2 * zkc.EPOCH_DURATION());

        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, mintAmount);

        assertEq(zkc.claimedTotalSupply(), zkc.INITIAL_SUPPLY() + mintAmount);
        assertEq(zkc.totalSupply(), Supply.getSupplyAtEpoch(2));
    }

    function testTotalSupplyVsClaimedSupplyGap() public {
        // Move to epoch 5
        vm.warp(vm.getBlockTimestamp() + 5 * zkc.EPOCH_DURATION());

        // Mint some rewards
        uint256 mintAmount = 1000 * 10 ** 18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, mintAmount);

        // totalSupply should be much higher than claimed
        uint256 theoretical = zkc.totalSupply();
        uint256 claimed = zkc.claimedTotalSupply();

        assertGt(theoretical, claimed);
        assertEq(theoretical, Supply.getSupplyAtEpoch(5));
        assertEq(claimed, zkc.INITIAL_SUPPLY() + mintAmount);
    }

    function testSuppliesWithMixedMinting() public {
        vm.warp(epoch0StartTime + 3 * zkc.EPOCH_DURATION());

        // PoVW reward mint
        uint256 povwAmount = 1000 * 10 ** 18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, povwAmount);

        // Staking reward mint
        uint256 stakingAmount = 500 * 10 ** 18;
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, stakingAmount);

        uint256 expectedClaimed = zkc.INITIAL_SUPPLY() + povwAmount + stakingAmount;
        assertEq(zkc.claimedTotalSupply(), expectedClaimed, "Claimed total supply should be the initial supply plus the minted amounts");
        assertEq(zkc.totalSupply(), Supply.getSupplyAtEpoch(3), "Total supply should be the supply at epoch 3");
        assertGt(zkc.totalSupply(), zkc.claimedTotalSupply(), "Total supply should be greater than claimed total supply");
    }

    function testTheoreticalSupplyGrowsWithTime() public {
        uint256 supplyEpoch0 = zkc.totalSupply();

        // Move to epoch 10
        vm.warp(epoch0StartTime + 10 * zkc.EPOCH_DURATION());
        uint256 supplyEpoch10 = zkc.totalSupply();

        // Move to epoch 100
        vm.warp(epoch0StartTime + 100 * zkc.EPOCH_DURATION());
        uint256 supplyEpoch100 = zkc.totalSupply();

        // Theoretical supply should grow over time
        assertGt(supplyEpoch10, supplyEpoch0);
        assertGt(supplyEpoch100, supplyEpoch10);

        // But claimed supply should remain the initial supply (no additional minting)
        assertEq(zkc.claimedTotalSupply(), zkc.INITIAL_SUPPLY());
    }

    function testSupplyFunctionsDelegation() public {
        // Test that totalSupply delegates to Supply library via getSupplyAtEpochStart
        vm.warp(epoch0StartTime + 50 * zkc.EPOCH_DURATION());

        uint256 currentEpoch = zkc.getCurrentEpoch();
        assertEq(zkc.totalSupply(), Supply.getSupplyAtEpoch(currentEpoch));
        assertEq(zkc.totalSupply(), zkc.getSupplyAtEpochStart(currentEpoch));
    }
}
