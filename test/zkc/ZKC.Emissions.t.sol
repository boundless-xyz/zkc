// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../ZKC.t.sol";
import "../../src/libraries/Supply.sol";
import {IZKC} from "../../src/interfaces/IZKC.sol";

contract ZKCEmissionsTest is ZKCTest {
    function setUp() public {
        deployZKC();
    }

    function testInitialMintByMinter1() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user;
        recipients[1] = makeAddr("user2");

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100_000 * 10 ** 18;
        amounts[1] = 200_000 * 10 ** 18;

        uint256 totalAmount = amounts[0] + amounts[1];
        uint256 minter1RemainingBefore = zkc.initialMinter1Remaining();

        vm.prank(minter1);
        zkc.initialMint(recipients, amounts);

        // Check balances
        assertEq(zkc.balanceOf(user), amounts[0]);
        assertEq(zkc.balanceOf(makeAddr("user2")), amounts[1]);

        // Check remaining amount updated
        assertEq(zkc.initialMinter1Remaining(), minter1RemainingBefore - totalAmount);
    }

    function testInitialMintByMinter2() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 150_000 * 10 ** 18;

        uint256 minter2RemainingBefore = zkc.initialMinter2Remaining();

        vm.prank(minter2);
        zkc.initialMint(recipients, amounts);

        // Check balance
        assertEq(zkc.balanceOf(user), amounts[0]);

        // Check remaining amount updated
        assertEq(zkc.initialMinter2Remaining(), minter2RemainingBefore - amounts[0]);
    }

    function testInitialMintExceedsRemaining() public {
        uint256 remaining = zkc.initialMinter1Remaining();

        address[] memory recipients = new address[](1);
        recipients[0] = user;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = remaining + 1;

        vm.expectRevert();
        vm.prank(minter1);
        zkc.initialMint(recipients, amounts);
    }

    function testInitialMintUnauthorized() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10 ** 18;

        vm.expectRevert();
        vm.prank(user);
        zkc.initialMint(recipients, amounts);
    }

    function testMintPoVWRewards() public {
        // Move to epoch 1 so there's allocation available (can't mint at epoch 0)
        vm.warp(epoch0StartTime + zkc.EPOCH_DURATION());

        uint256 amount = 1000 * 10 ** 18;
        uint256 balanceBefore = zkc.balanceOf(user);
        uint256 poVWClaimedBefore = zkc.poVWClaimed();
        assertEq(poVWClaimedBefore, 0);

        vm.expectEmit(true, true, false, true);
        emit IZKC.PoVWRewardsClaimed(user, amount);

        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amount);

        // Check balance increased
        assertEq(zkc.balanceOf(user), balanceBefore + amount);

        // Check tracking updated
        assertEq(zkc.poVWClaimed(), poVWClaimedBefore + amount);
    }

    function testMintStakingRewards() public {
        // Move to epoch 1 so there's allocation available (can't mint at epoch 0)
        vm.warp(epoch0StartTime + zkc.EPOCH_DURATION());

        uint256 amount = 500 * 10 ** 18;
        uint256 balanceBefore = zkc.balanceOf(user);
        uint256 stakingClaimedBefore = zkc.stakingClaimed();
        assertEq(stakingClaimedBefore, 0);

        vm.expectEmit(true, true, false, true);
        emit IZKC.StakingRewardsClaimed(user, amount);

        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amount);

        // Check balance increased
        assertEq(zkc.balanceOf(user), balanceBefore + amount);

        // Check tracking updated
        assertEq(zkc.stakingClaimed(), stakingClaimedBefore + amount);
    }

    function testMintPoVWRewardsExceedsTotalAllocation() public {
        // Fast forward to build up significant allocation
        vm.warp(epoch0StartTime + 365 days);

        uint256 currentEpoch = zkc.getCurrentEpoch();
        uint256 totalAllocation = zkc.getTotalPoVWEmissionsAtEpochStart(currentEpoch);

        // Try to mint more than total allocation
        uint256 excessAmount = totalAllocation + 1;

        vm.expectRevert(IZKC.TotalAllocationExceeded.selector);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, excessAmount);
    }

    function testMintStakingRewardsExceedsTotalAllocation() public {
        // Fast forward to build up significant allocation
        vm.warp(epoch0StartTime + 365 days);

        uint256 currentEpoch = zkc.getCurrentEpoch();
        uint256 totalAllocation = zkc.getTotalStakingEmissionsAtEpochStart(currentEpoch);

        // Try to mint more than total allocation
        uint256 excessAmount = totalAllocation + 1;

        vm.expectRevert(IZKC.TotalAllocationExceeded.selector);
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, excessAmount);
    }

    function testMintRewardsUnauthorized() public {
        uint256 amount = 1000 * 10 ** 18;

        // User cannot mint PoVW rewards
        vm.expectRevert();
        vm.prank(user);
        zkc.mintPoVWRewardsForRecipient(user, amount);

        // User cannot mint staking rewards
        vm.expectRevert();
        vm.prank(user);
        zkc.mintStakingRewardsForRecipient(user, amount);

        // Staking minter cannot mint PoVW rewards
        vm.expectRevert();
        vm.prank(stakingMinter);
        zkc.mintPoVWRewardsForRecipient(user, amount);

        // PoVW minter cannot mint staking rewards
        vm.expectRevert();
        vm.prank(povwMinter);
        zkc.mintStakingRewardsForRecipient(user, amount);
    }

    function testEmissionCalculations() public {
        uint256 epoch = 10;

        uint256 totalEmission = zkc.getEmissionsForEpoch(epoch);
        uint256 povwEmission = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 stakingEmission = zkc.getStakingEmissionsForEpoch(epoch);

        assertGt(totalEmission, 0, "Total emission should be positive");

        // Check allocations
        uint256 expectedPoVW = (totalEmission * zkc.POVW_ALLOCATION_BPS()) / zkc.BASIS_POINTS();
        uint256 expectedStaking = (totalEmission * zkc.STAKING_ALLOCATION_BPS()) / zkc.BASIS_POINTS();

        assertEq(povwEmission, expectedPoVW, "PoVW allocation mismatch");
        assertEq(stakingEmission, expectedStaking, "Staking allocation mismatch");
        assertEq(povwEmission + stakingEmission, totalEmission, "Allocations should sum to total");
    }

    function testTotalEmissionsCalculations() public {
        uint256 epoch = 10;
        uint256 totalEmission = zkc.getSupplyAtEpochStart(epoch);
        uint256 povwEmission = zkc.getTotalPoVWEmissionsAtEpochStart(epoch);
        uint256 stakingEmission = zkc.getTotalStakingEmissionsAtEpochStart(epoch);
        
        assertEq(povwEmission, (totalEmission - zkc.INITIAL_SUPPLY()) * zkc.POVW_ALLOCATION_BPS() / zkc.BASIS_POINTS());
        assertEq(stakingEmission, (totalEmission - zkc.INITIAL_SUPPLY()) * zkc.STAKING_ALLOCATION_BPS() / zkc.BASIS_POINTS());
        assertEq(totalEmission - zkc.INITIAL_SUPPLY(), povwEmission + stakingEmission);
    }

    function testEpochFunctions() public {
        uint256 currentEpoch = zkc.getCurrentEpoch();
        assertEq(currentEpoch, 0, "Should start at epoch 0");

        uint256 epochStartTime = zkc.getEpochStartTime(currentEpoch);
        assertEq(epochStartTime, epoch0StartTime, "Epoch 0 should start at deployment time");

        uint256 epochEndTime = zkc.getEpochEndTime(currentEpoch);
        assertEq(epochEndTime, epoch0StartTime + zkc.EPOCH_DURATION() - 1, "Epoch end time calculation");

        // Fast forward and check epoch progression
        vm.warp(epoch0StartTime + zkc.EPOCH_DURATION() + 1);
        assertEq(zkc.getCurrentEpoch(), 1, "Should progress to epoch 1");
    }

    function testSupplyFunctionsDelegation() public {
        // Test that ZKC functions delegate correctly to Supply library
        uint256 epoch = 10;

        assertEq(zkc.getSupplyAtEpochStart(epoch), Supply.getSupplyAtEpoch(epoch), "Supply delegation");
        assertEq(zkc.getEmissionsForEpoch(epoch), Supply.getEmissionsForEpoch(epoch), "Emissions delegation");
    }
}
