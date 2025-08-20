// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/libraries/Supply.sol";
import {UD60x18, ud, unwrap, pow} from "lib/prb-math/src/UD60x18.sol";

/// @dev Wrapper contract to expose Supply library functions as external for gas snapshots
contract SupplyWrapper {
    using Supply for *;

    function getSupplyAtEpoch(uint256 epoch) external pure returns (uint256) {
        return Supply.getSupplyAtEpoch(epoch);
    }

    function getEmissionsForEpoch(uint256 epoch) external returns (uint256) {
        return Supply.getEmissionsForEpoch(epoch);
    }
}

contract SupplyTest is Test {
    using Supply for *;

    SupplyWrapper public wrapper;

    uint256 constant SCALE = 1e18;
    uint256 constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 constant EPOCHS_PER_YEAR = 182;

    function setUp() public {
        wrapper = new SupplyWrapper();
    }

    function testInitialSupply() public {
        assertEq(Supply.getSupplyAtEpoch(0), INITIAL_SUPPLY);
        assertEq(Supply.SUPPLY_YEAR_0, INITIAL_SUPPLY);
    }

    function testYearBoundarySupplyYear1() public {
        // Compute supply at year 1 boundary (epoch 182) manually
        UD60x18 supplyUD = ud(INITIAL_SUPPLY);
        UD60x18 factorUD = ud(Supply.Y0_R_PER_EPOCH);
        UD60x18 epochsUD = ud(182 * SCALE);
        UD60x18 multiplierUD = pow(factorUD, epochsUD);
        UD60x18 resultUD = supplyUD * multiplierUD / ud(SCALE);
        uint256 expectedSupply = unwrap(resultUD);

        assertEq(Supply.SUPPLY_YEAR_1, expectedSupply);
        assertEq(Supply.getSupplyAtEpoch(182), Supply.SUPPLY_YEAR_1);
    }

    function testYearBoundarySupplyYear9() public {
        // Start from Year 8 and apply Year 8 growth using PRBMath
        UD60x18 supplyUD = ud(Supply.SUPPLY_YEAR_8);
        UD60x18 factorUD = ud(Supply.Y8_R_PER_EPOCH);
        UD60x18 epochsUD = ud(182 * SCALE);
        UD60x18 multiplierUD = pow(factorUD, epochsUD);
        UD60x18 resultUD = supplyUD * multiplierUD / ud(SCALE);
        uint256 expectedSupply = unwrap(resultUD);

        assertEq(Supply.SUPPLY_YEAR_9, expectedSupply);
        assertEq(Supply.getSupplyAtEpoch(1638), Supply.SUPPLY_YEAR_9);
    }

    function testMidYearSupplyCalculations() public {
        // Test supply at various mid-year points using PRBMath for expected values

        // Epoch 91 (middle of Year 0)
        UD60x18 supplyUD = ud(INITIAL_SUPPLY);
        UD60x18 factorUD = ud(Supply.Y0_R_PER_EPOCH);
        UD60x18 epochsUD = ud(91 * SCALE);
        UD60x18 multiplierUD = pow(factorUD, epochsUD);
        UD60x18 resultUD = supplyUD * multiplierUD / ud(SCALE);
        uint256 expectedSupply = unwrap(resultUD);

        assertEq(Supply.getSupplyAtEpoch(91), expectedSupply);

        // Epoch 273 (middle of Year 1, epoch 182 + 91)
        supplyUD = ud(Supply.SUPPLY_YEAR_1);
        factorUD = ud(Supply.Y1_R_PER_EPOCH);
        epochsUD = ud(91 * SCALE);
        multiplierUD = pow(factorUD, epochsUD);
        resultUD = supplyUD * multiplierUD / ud(SCALE);
        expectedSupply = unwrap(resultUD);

        assertEq(Supply.getSupplyAtEpoch(273), expectedSupply);

        // Epoch 455 (middle of Year 2, epoch 364 + 91)
        supplyUD = ud(Supply.SUPPLY_YEAR_2);
        factorUD = ud(Supply.Y2_R_PER_EPOCH);
        epochsUD = ud(91 * SCALE);
        multiplierUD = pow(factorUD, epochsUD);
        resultUD = supplyUD * multiplierUD / ud(SCALE);
        expectedSupply = unwrap(resultUD);

        assertEq(Supply.getSupplyAtEpoch(455), expectedSupply);
    }

    function testGetYearForEpoch() public {
        assertEq(Supply.getYearForEpoch(0), 0, "Epoch 0 should be Year 0");
        assertEq(Supply.getYearForEpoch(181), 0, "Epoch 181 should be Year 0");
        assertEq(Supply.getYearForEpoch(182), 1, "Epoch 182 should be Year 1");
        assertEq(Supply.getYearForEpoch(363), 1, "Epoch 363 should be Year 1");
        assertEq(Supply.getYearForEpoch(364), 2, "Epoch 364 should be Year 2");
        assertEq(Supply.getYearForEpoch(545), 2, "Epoch 545 should be Year 2");
        assertEq(Supply.getYearForEpoch(546), 3, "Epoch 546 should be Year 3");
        assertEq(Supply.getYearForEpoch(1456), 8, "Epoch 1456 should be Year 8");
        assertEq(Supply.getYearForEpoch(1638), 9, "Epoch 1638 should be Year 9");
    }

    function testGetEmissionsForEpoch() public {
        uint256 emission1 = Supply.getEmissionsForEpoch(0);
        assertGt(emission1, 0);

        // Later emissions in same year should be larger.
        uint256 emission100 = Supply.getEmissionsForEpoch(100);
        assertGt(emission100, emission1);

        uint256 supplyBefore = Supply.getSupplyAtEpoch(99);
        uint256 supplyAfter = Supply.getSupplyAtEpoch(100);
        assertEq(Supply.getEmissionsForEpoch(99), supplyAfter - supplyBefore);
    }

    function testConsistencyAcrossYearBoundaries() public {
        // Verify supply calculation is as expected across year boundaries

        // Test around Year 0/1 boundary
        uint256 supply181 = Supply.getSupplyAtEpoch(181);
        uint256 supply182 = Supply.getSupplyAtEpoch(182);

        // Calculate expected value using PRBMath (same as library)
        UD60x18 supply181UD = ud(supply181);
        UD60x18 factorUD = ud(Supply.Y0_R_PER_EPOCH);
        UD60x18 epochsUD = ud(1 * SCALE); // 1 epoch difference
        UD60x18 multiplierUD = pow(factorUD, epochsUD);
        UD60x18 expectedUD = supply181UD * multiplierUD / ud(SCALE);
        uint256 expectedSupply182 = unwrap(expectedUD);

        // Allow small precision difference due to PRBMath's Taylor series approximation vs exact hardcoded values
        // supply182 = hardcoded constant (generated using PRBMath exponentiation in script)
        // expectedSupply182 = PRBMath calculation from supply181 
        uint256 diff = supply182 > expectedSupply182 ? supply182 - expectedSupply182 : expectedSupply182 - supply182;
        uint256 tolerance = supply182 / 1000000; // 0.0001% tolerance for PRBMath precision
        assertLt(diff, tolerance, "Supply should be continuous at year boundary within PRBMath precision");

        // Test around Year 1/2 boundary
        uint256 supply363 = Supply.getSupplyAtEpoch(363);
        uint256 supply364 = Supply.getSupplyAtEpoch(364);

        // Calculate expected value using PRBMath
        UD60x18 supply363UD = ud(supply363);
        UD60x18 factor1UD = ud(Supply.Y1_R_PER_EPOCH);
        UD60x18 epochs1UD = ud(1 * SCALE); // 1 epoch difference
        UD60x18 multiplier1UD = pow(factor1UD, epochs1UD);
        UD60x18 expected1UD = supply363UD * multiplier1UD / ud(SCALE);
        uint256 expectedSupply364 = unwrap(expected1UD);

        // Apply same precision tolerance for Year 1/2 boundary
        uint256 diff1 = supply364 > expectedSupply364 ? supply364 - expectedSupply364 : expectedSupply364 - supply364;
        uint256 tolerance1 = supply364 / 1000000; // 0.0001% tolerance for PRBMath precision
        assertLt(diff1, tolerance1, "Supply should be continuous at year 1/2 boundary within PRBMath precision");
    }

    function testManualGrowthFactorApplication() public {
        // Verify that PRBMath growth factor application gives us the hardcoded yearly values
        uint256 supply = INITIAL_SUPPLY;

        // Test Year 0 -> Year 1
        assertEq(supply, Supply.SUPPLY_YEAR_0, "Year 0 should match initial supply");

        // Apply Y0 factor for 182 epochs using PRBMath
        UD60x18 supplyUD = ud(supply);
        UD60x18 factorUD = ud(Supply.Y0_R_PER_EPOCH);
        UD60x18 epochsUD = ud(182 * SCALE);
        UD60x18 multiplierUD = pow(factorUD, epochsUD);
        UD60x18 resultUD = supplyUD * multiplierUD / ud(SCALE);
        supply = unwrap(resultUD);

        assertEq(supply, Supply.SUPPLY_YEAR_1, "PRBMath Year 1 calculation should match hardcoded value");

        // Apply Y1 factor for 182 epochs using PRBMath
        supplyUD = ud(supply);
        factorUD = ud(Supply.Y1_R_PER_EPOCH);
        epochsUD = ud(182 * SCALE);
        multiplierUD = pow(factorUD, epochsUD);
        resultUD = supplyUD * multiplierUD / ud(SCALE);
        supply = unwrap(resultUD);

        assertEq(supply, Supply.SUPPLY_YEAR_2, "PRBMath Year 2 calculation should match hardcoded value");

        // Apply Y2 factor for 182 epochs using PRBMath
        supplyUD = ud(supply);
        factorUD = ud(Supply.Y2_R_PER_EPOCH);
        epochsUD = ud(182 * SCALE);
        multiplierUD = pow(factorUD, epochsUD);
        resultUD = supplyUD * multiplierUD / ud(SCALE);
        supply = unwrap(resultUD);

        assertEq(supply, Supply.SUPPLY_YEAR_3, "PRBMath Year 3 calculation should match hardcoded value");

        // Test all remaining years
        uint256[6] memory factors = [
            Supply.Y3_R_PER_EPOCH, // Year 3 -> 4
            Supply.Y4_R_PER_EPOCH, // Year 4 -> 5
            Supply.Y5_R_PER_EPOCH, // Year 5 -> 6
            Supply.Y6_R_PER_EPOCH, // Year 6 -> 7
            Supply.Y7_R_PER_EPOCH, // Year 7 -> 8
            Supply.Y8_R_PER_EPOCH // Year 8 -> 9
        ];

        uint256[6] memory hardcodedSupplies = [
            Supply.SUPPLY_YEAR_4,
            Supply.SUPPLY_YEAR_5,
            Supply.SUPPLY_YEAR_6,
            Supply.SUPPLY_YEAR_7,
            Supply.SUPPLY_YEAR_8,
            Supply.SUPPLY_YEAR_9
        ];

        for (uint256 i = 0; i < factors.length; i++) {
            // Apply factor for 182 epochs using PRBMath
            supplyUD = ud(supply);
            factorUD = ud(factors[i]);
            epochsUD = ud(182 * SCALE);
            multiplierUD = pow(factorUD, epochsUD);
            resultUD = supplyUD * multiplierUD / ud(SCALE);
            supply = unwrap(resultUD);

            uint256 year = i + 4; // Years 4-9
            console.log("Year %s supply (PRBMath): %s", year, supply);
            console.log("Year %s supply (hardcoded): %s", year, hardcodedSupplies[i]);
            assertEq(
                supply,
                hardcodedSupplies[i],
                string(abi.encodePacked("PRBMath Year ", year, " calculation should match hardcoded value"))
            );
        }
    }

    function testManualLoopsVsLibrary() public {
        // Compare manual loop calculations with library function to ensure consistency
        uint256[] memory testEpochs = new uint256[](4);
        testEpochs[0] = 50; // Mid Year 0
        testEpochs[1] = 91; // Mid Year 0
        testEpochs[2] = 273; // Mid Year 1 (182 + 91)
        testEpochs[3] = 455; // Mid Year 2 (364 + 91)

        for (uint256 i = 0; i < testEpochs.length; i++) {
            uint256 epoch = testEpochs[i];

            // Manual calculation from epoch 0 to epoch N
            uint256 manualSupply = INITIAL_SUPPLY;
            for (uint256 j = 1; j <= epoch; j++) {
                uint256 currentYear = (j - 1) / EPOCHS_PER_YEAR;
                uint256 currentGrowthFactor;

                if (currentYear == 0) currentGrowthFactor = Supply.Y0_R_PER_EPOCH;
                else if (currentYear == 1) currentGrowthFactor = Supply.Y1_R_PER_EPOCH;
                else if (currentYear == 2) currentGrowthFactor = Supply.Y2_R_PER_EPOCH;
                else if (currentYear == 3) currentGrowthFactor = Supply.Y3_R_PER_EPOCH;
                else currentGrowthFactor = Supply.FINAL_R_PER_EPOCH;

                manualSupply = (manualSupply * currentGrowthFactor) / SCALE;
            }

            // Library function result (uses manual loops internally with optimization)
            uint256 librarySupply = Supply.getSupplyAtEpoch(epoch);

            // Calculate difference and verify it's within tolerance
            uint256 diff = manualSupply > librarySupply ? manualSupply - librarySupply : librarySupply - manualSupply;

            // Allow small precision differences between manual loops and PRBMath exponentiation
            // Tolerance: 0.001% of the total supply
            uint256 tolerance = manualSupply / 100000; // 0.001%
            assertLt(diff, tolerance, "Manual and library calculations should be close within tolerance");
        }
    }

    function testSupplyYear15() public {
        // Test year 15 boundary (epoch 2730 = 15 * 182)
        uint256 epochYear15 = 15 * EPOCHS_PER_YEAR;
        uint256 supplyYear15 = Supply.getSupplyAtEpoch(epochYear15);

        // Calculate expected: SUPPLY_YEAR_9 * (1.03)^6
        // Year 15 = Year 9 + 6 years of 3% growth
        UD60x18 supply9 = ud(Supply.SUPPLY_YEAR_9);
        UD60x18 factor = ud(Supply.FINAL_R_PER_EPOCH);
        UD60x18 epochs = ud(6 * EPOCHS_PER_YEAR * SCALE);
        UD60x18 multiplier = pow(factor, epochs);
        UD60x18 result = supply9 * multiplier / ud(SCALE);
        uint256 expected = unwrap(result);

        assertEq(supplyYear15, expected, "Year 15 supply should match calculation");

        // Test mid-year 15 (epoch 2821 = 2730 + 91)
        uint256 epochMidYear15 = epochYear15 + 91;
        uint256 supplyMidYear15 = Supply.getSupplyAtEpoch(epochMidYear15);

        // Calculate expected: supplyYear15 * factor^91
        UD60x18 supplyYear15UD = ud(supplyYear15);
        UD60x18 epochs91 = ud(91 * SCALE);
        UD60x18 multiplier91 = pow(factor, epochs91);
        UD60x18 resultMid = supplyYear15UD * multiplier91 / ud(SCALE);
        uint256 expectedMid = unwrap(resultMid);

        assertEq(supplyMidYear15, expectedMid, "Mid-year 15 supply should match calculation");
        assertGt(supplyMidYear15, supplyYear15, "Mid-year should be greater than year boundary");
    }

    // Gas snapshot tests for getSupplyAtEpoch
    function testGasGetSupplyAtEpoch_Year1Start() public {
        wrapper.getSupplyAtEpoch(182); // Year 1 start
        vm.snapshotGasLastCall("getSupplyAtEpoch: Year 1 start");
    }

    function testGasGetSupplyAtEpoch_Year1Mid() public {
        wrapper.getSupplyAtEpoch(273); // Year 1 mid (182 + 91)
        vm.snapshotGasLastCall("getSupplyAtEpoch: Year 1 mid");
    }

    function testGasGetSupplyAtEpoch_Year15Start() public {
        wrapper.getSupplyAtEpoch(2730); // Year 15 start (15 * 182)
        vm.snapshotGasLastCall("getSupplyAtEpoch: Year 15 start");
    }

    function testGasGetSupplyAtEpoch_Year15Mid() public {
        wrapper.getSupplyAtEpoch(2821); // Year 15 mid (2730 + 91)
        vm.snapshotGasLastCall("getSupplyAtEpoch: Year 15 mid");
    }

    // Gas snapshot tests for getEmissionsForEpoch
    function testGasGetEmissionsForEpoch_Year1Mid() public {
        wrapper.getEmissionsForEpoch(273); // Year 1 mid
        vm.snapshotGasLastCall("getEmissionsForEpoch: Year 1 mid");
    }

    function testGasGetEmissionsForEpoch_Year15Mid() public {
        wrapper.getEmissionsForEpoch(2821); // Year 15 mid
        vm.snapshotGasLastCall("getEmissionsForEpoch: Year 15 mid");
    }
}
