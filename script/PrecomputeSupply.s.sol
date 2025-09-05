// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {UD60x18, ud, unwrap, pow, ln, exp} from "lib/prb-math/src/UD60x18.sol";

contract PrecomputeSupply is Script {
    using {unwrap} for UD60x18;

    uint256 constant EPOCHS_PER_YEAR = 182;
    uint256 constant INITIAL_SUPPLY = 1_000_000_000 * 1e18;

    function run() external pure {
        console.log("============================================================");
        console.log("Precomputing ZKC Supply Constants with PRBMath UD60x18");
        console.log("============================================================");
        console.log("");

        // Annual rates as UD60x18 (1.07 = 1.07e18)
        UD60x18[9] memory annualRates = [
            ud(1.07e18), // Year 0: 7.0%
            ud(1.065e18), // Year 1: 6.5%
            ud(1.06e18), // Year 2: 6.0%
            ud(1.055e18), // Year 3: 5.5%
            ud(1.05e18), // Year 4: 5.0%
            ud(1.045e18), // Year 5: 4.5%
            ud(1.04e18), // Year 6: 4.0%
            ud(1.035e18), // Year 7: 3.5%
            ud(1.03e18) // Year 8+: 3.0%
        ];

        uint256[9] memory epochFactors;

        console.log("Computing per-epoch factors using PRBMath pow():");
        console.log("");

        for (uint256 i = 0; i < annualRates.length; i++) {
            // Calculate (1 + rate)^(1/182) using ln and exp
            // x^(1/n) = exp(ln(x) / n)
            // (1 + rate)^(1/182) = exp(ln(1 + rate) / 182)

            UD60x18 lnRate = ln(annualRates[i]);
            UD60x18 epochs = ud(uint256(EPOCHS_PER_YEAR) * 1e18); // Scale 182 to UD60x18
            UD60x18 exponent = lnRate / epochs;
            UD60x18 factor = exp(exponent);

            epochFactors[i] = uint256(factor.unwrap());

            // Verify by raising to power of 182
            UD60x18 verification = pow(factor, epochs);

            console.log("Year %s:", i);
            console.log("  Target annual rate: %s", uint256(annualRates[i].unwrap()));
            console.log("  Per-epoch factor: %s", epochFactors[i]);
            console.log("  Verification (factor^182): %s", uint256(verification.unwrap()));

            // Show the difference from target
            uint256 target = uint256(annualRates[i].unwrap());
            uint256 actual = uint256(verification.unwrap());
            uint256 error = actual > target ? actual - target : target - actual;
            console.log("  Error: %s", error);
            console.log("");
        }

        console.log("============================================================");
        console.log("SUPPLY AT YEAR BOUNDARIES:");
        console.log("============================================================");
        console.log("");

        uint256 supply = INITIAL_SUPPLY;
        console.log("Year 0 (Epoch 0): %s", supply);

        uint256[10] memory supplyBoundaries;
        supplyBoundaries[0] = supply;

        for (uint256 year = 0; year < epochFactors.length; year++) {
            // Use PRBMath exponentiation instead of manual loops for consistency with library
            UD60x18 supplyUD = ud(supply);
            UD60x18 factorUD = ud(epochFactors[year]);
            UD60x18 epochsUD = ud(EPOCHS_PER_YEAR * 1e18); // Scale epochs for PRBMath
            UD60x18 multiplierUD = pow(factorUD, epochsUD);
            UD60x18 resultUD = supplyUD * multiplierUD / ud(1e18);
            supply = unwrap(resultUD);

            uint256 nextYear = year + 1;
            uint256 nextEpoch = nextYear * EPOCHS_PER_YEAR;
            supplyBoundaries[nextYear] = supply;
            console.log("Year %s (Epoch %s): %s", nextYear, nextEpoch, supply);
        }

        console.log("");
        console.log("============================================================");
        console.log("SOLIDITY CONSTANTS:");
        console.log("============================================================");
        console.log("");

        console.log("// Precomputed per-epoch growth factors (calculated with PRBMath)");
        for (uint256 i = 0; i < epochFactors.length; i++) {
            console.log("uint256 public constant Y%s_R_PER_EPOCH = %s; // Year %s", i, epochFactors[i], i);
        }

        console.log("");
        console.log("uint256 public constant FINAL_R_PER_EPOCH = %s; // 3.0%% annual", epochFactors[8]);

        console.log("");
        console.log("// Precomputed supply values at year boundaries");
        for (uint256 i = 0; i < supplyBoundaries.length; i++) {
            if (i == 0) {
                console.log("uint256 public constant SUPPLY_YEAR_%s = %s; // Initial supply", i, supplyBoundaries[i]);
            } else {
                uint256 epoch = i * EPOCHS_PER_YEAR;
                console.log(
                    "uint256 public constant SUPPLY_YEAR_%s = %s; // Supply at epoch %s", i, supplyBoundaries[i], epoch
                );
            }
        }
    }
}
