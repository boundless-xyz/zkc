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

        vm.warp(epoch0StartTime + 1 days);
        assertEq(zkc.getCurrentEpoch(), 0);

        vm.warp(epoch0StartTime + 2 days - 1 seconds);
        assertEq(zkc.getCurrentEpoch(), 0);

        vm.warp(epoch0StartTime + 2 days);
        assertEq(zkc.getCurrentEpoch(), 1);

        vm.warp(epoch0StartTime + 4 days);
        assertEq(zkc.getCurrentEpoch(), 2);

        vm.warp(epoch0StartTime + 365 days);
        assertEq(zkc.getCurrentEpoch(), 182);
    }

    function testGetEpochStartTime() public view {
        assertEq(zkc.getEpochStartTime(0), epoch0StartTime);
        assertEq(zkc.getEpochStartTime(1), epoch0StartTime + zkc.EPOCH_DURATION());
        assertEq(zkc.getEpochStartTime(10), epoch0StartTime + (10 * zkc.EPOCH_DURATION()));

        uint256 epoch = 1000;
        uint256 expectedStartTime = epoch0StartTime + (epoch * zkc.EPOCH_DURATION());
        assertEq(zkc.getEpochStartTime(epoch), expectedStartTime);
        assertEq(zkc.getEpochStartTime(epoch + 1), zkc.getEpochStartTime(epoch) + zkc.EPOCH_DURATION());
    }

    function testGetEpochEndTime() public view {
        assertEq(zkc.getEpochEndTime(0), epoch0StartTime + zkc.EPOCH_DURATION() - 1);
        assertEq(zkc.getEpochEndTime(1), epoch0StartTime + 2 * zkc.EPOCH_DURATION() - 1);

        uint256 epoch = 100;
        uint256 expectedEndTime = epoch0StartTime + (epoch + 1) * zkc.EPOCH_DURATION() - 1;
        assertEq(zkc.getEpochEndTime(epoch), expectedEndTime);
    }

    function testGetSupplyAtEpochStart() public view {
        assertEq(zkc.getSupplyAtEpochStart(0), zkc.INITIAL_SUPPLY());
        // Confirm delegation to Supply library
        assertEq(zkc.getSupplyAtEpochStart(100), Supply.getSupplyAtEpoch(100));
        assertEq(zkc.getSupplyAtEpochStart(182), Supply.getSupplyAtEpoch(182));
        assertEq(zkc.getSupplyAtEpochStart(1000), Supply.getSupplyAtEpoch(1000));
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

        uint256 expectedStaking = (totalEmission * zkc.STAKING_ALLOCATION_BPS()) / zkc.BASIS_POINTS();
        assertEq(stakingEmission, expectedStaking);
    }

    function testGetTotalPoVWEmissionsAtEpochStart() public {
        uint256 epoch = 10;

        // getTotalPoVWEmissionsAtEpochStart returns emissions up to START of epoch (not end)
        uint256 totalEmissions = zkc.getSupplyAtEpochStart(epoch) - zkc.INITIAL_SUPPLY();
        uint256 expectedPoVW = (totalEmissions * zkc.POVW_ALLOCATION_BPS()) / zkc.BASIS_POINTS();

        assertEq(zkc.getTotalPoVWEmissionsAtEpochStart(epoch), expectedPoVW);
    }

    function testGetTotalStakingEmissionsAtEpochStart() public {
        uint256 epoch = 10;

        // getTotalStakingEmissionsAtEpochStart returns emissions up to START of epoch (not end)
        uint256 totalEmissions = zkc.getSupplyAtEpochStart(epoch) - zkc.INITIAL_SUPPLY();
        uint256 expectedStaking = (totalEmissions * zkc.STAKING_ALLOCATION_BPS()) / zkc.BASIS_POINTS();

        assertEq(zkc.getTotalStakingEmissionsAtEpochStart(epoch), expectedStaking);
    }

    function testEpochProgressionAffectsAllocations() public {
        uint256 epoch0 = 0;
        uint256 epoch10 = 10;
        uint256 epoch100 = 100;

        uint256 totalPoVW0 = zkc.getTotalPoVWEmissionsAtEpochStart(epoch0);
        uint256 totalPoVW10 = zkc.getTotalPoVWEmissionsAtEpochStart(epoch10);
        uint256 totalPoVW100 = zkc.getTotalPoVWEmissionsAtEpochStart(epoch100);

        // Later epochs should have higher total allocations due to inflation
        assertGt(totalPoVW10, totalPoVW0);
        assertGt(totalPoVW100, totalPoVW10);

        uint256 totalStaking0 = zkc.getTotalStakingEmissionsAtEpochStart(epoch0);
        uint256 totalStaking10 = zkc.getTotalStakingEmissionsAtEpochStart(epoch10);
        uint256 totalStaking100 = zkc.getTotalStakingEmissionsAtEpochStart(epoch100);

        assertGt(totalStaking10, totalStaking0);
        assertGt(totalStaking100, totalStaking10);
    }

    function testSupplyGrowthOverTime() public view {
        uint256 initialSupply = zkc.INITIAL_SUPPLY();
        uint256 supplyAfter1Year = zkc.getSupplyAtEpochStart(182);
        uint256 supplyAfter2Years = zkc.getSupplyAtEpochStart(364);

        assertGt(supplyAfter1Year, initialSupply);
        assertGt(supplyAfter2Years, supplyAfter1Year);
    }

    function testGetCurrentEpochEndTime() public {
        vm.warp(epoch0StartTime + 1 days);
        assertEq(zkc.getCurrentEpochEndTime(), epoch0StartTime + zkc.EPOCH_DURATION() - 1);

        vm.warp(epoch0StartTime + 2 days - 1 seconds);
        assertEq(zkc.getCurrentEpochEndTime(), epoch0StartTime + zkc.EPOCH_DURATION() - 1);

        vm.warp(epoch0StartTime + 2 days);
        assertEq(zkc.getCurrentEpochEndTime(), epoch0StartTime + 2 * zkc.EPOCH_DURATION() - 1);

        vm.warp(epoch0StartTime + 365 days);
        uint256 currentEpoch = zkc.getCurrentEpoch();
        uint256 expectedEndTime = epoch0StartTime + (currentEpoch + 1) * zkc.EPOCH_DURATION() - 1;
        assertEq(zkc.getCurrentEpochEndTime(), expectedEndTime);
    }
}
