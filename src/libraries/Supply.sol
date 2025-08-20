// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UD60x18, ud, unwrap, pow} from "lib/prb-math/src/UD60x18.sol";

/// @title ZKC Supply Library
/// @notice Library for calculating ZKC supply and emissions based on epoch
/// @dev Annual supply values and epoch scaling factors per year are precomputed for gas efficiency.
/// Precomputed values were created by running the script/PrecomputeSupply.s.sol script.
/// 
/// Inflation schedule:
/// - Year 0: 7.0% annual, reduces by 0.5% each year
/// - Year 8+: 3.0% annual (minimum rate)
library Supply {
    // Base constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18; // 1 billion ZKC
    uint256 public constant EPOCHS_PER_YEAR = 182;
    uint256 public constant SCALE = 1e18; // Fixed-point scale
    
    // Precomputed per-epoch growth factors (1e18 scaled)
    // Calculated with PRBMath UD60x18: r = (1 + annual_rate)^(1/182)
    uint256 public constant Y0_R_PER_EPOCH = 1000371819923688085; // Year 0: 7.000% annual
    uint256 public constant Y1_R_PER_EPOCH = 1000346075250234369; // Year 1: 6.500% annual
    uint256 public constant Y2_R_PER_EPOCH = 1000320210092156012; // Year 2: 6.000% annual
    uint256 public constant Y3_R_PER_EPOCH = 1000294223313256956; // Year 3: 5.500% annual
    uint256 public constant Y4_R_PER_EPOCH = 1000268113761178075; // Year 4: 5.000% annual
    uint256 public constant Y5_R_PER_EPOCH = 1000241880267088989; // Year 5: 4.500% annual
    uint256 public constant Y6_R_PER_EPOCH = 1000215521645372515; // Year 6: 4.000% annual
    uint256 public constant Y7_R_PER_EPOCH = 1000189036693301502; // Year 7: 3.500% annual
    uint256 public constant Y8_R_PER_EPOCH = 1000162424190707866; // Year 8+: 3.000% annual
    
    // Year 8 and beyond use the minimum 3% rate
    uint256 public constant FINAL_R_PER_EPOCH = 1000162424190707866; // 3.000% annual (minimum)
    
    // Precomputed supply values at year boundaries for optimization
    // These values represent the total supply at the START of each year
    // Calculated using PRBMath exponentiation for consistency with library calculations
    uint256 public constant SUPPLY_YEAR_0 = 1000000000000000000000000000; // Initial supply
    uint256 public constant SUPPLY_YEAR_1 = 1069999999999998184000000000; // Supply at epoch 182
    uint256 public constant SUPPLY_YEAR_2 = 1139549999999995737640000000; // Supply at epoch 364
    uint256 public constant SUPPLY_YEAR_3 = 1207922999999993680269850000; // Supply at epoch 546
    uint256 public constant SUPPLY_YEAR_4 = 1274358764999991093195449750; // Supply at epoch 728
    uint256 public constant SUPPLY_YEAR_5 = 1338076703249988310681247227; // Supply at epoch 910
    uint256 public constant SUPPLY_YEAR_6 = 1398290154896235164707718388; // Supply at epoch 1092
    uint256 public constant SUPPLY_YEAR_7 = 1454221761092082452886442455; // Supply at epoch 1274
    uint256 public constant SUPPLY_YEAR_8 = 1505119522730302372125075313; // Supply at epoch 1456
    uint256 public constant SUPPLY_YEAR_9 = 1550273108412208360804045020; // Supply at epoch 1638
    
    /// @notice Get the per-epoch growth factor for a given epoch
    /// @param epoch The epoch number (0-indexed)
    /// @return The growth factor scaled by 1e18
    function getGrowthFactor(uint256 epoch) internal pure returns (uint256) {
        if (epoch == 0) return SCALE; // No growth for epoch 0
        
        // Determine which year this epoch falls into (0-indexed)
        uint256 year = epoch / EPOCHS_PER_YEAR;
        
        if (year == 0) return Y0_R_PER_EPOCH;
        if (year == 1) return Y1_R_PER_EPOCH;
        if (year == 2) return Y2_R_PER_EPOCH;
        if (year == 3) return Y3_R_PER_EPOCH;
        if (year == 4) return Y4_R_PER_EPOCH;
        if (year == 5) return Y5_R_PER_EPOCH;
        if (year == 6) return Y6_R_PER_EPOCH;
        if (year == 7) return Y7_R_PER_EPOCH;
        
        // Year 8 and beyond use the minimum rate (3%)
        return FINAL_R_PER_EPOCH;
    }
    
    /// @notice Calculate the total supply at the start of a given epoch
    /// @param epoch The epoch number (0-indexed)
    /// @return The total supply at the start of the epoch
    function getSupplyAtEpoch(uint256 epoch) internal pure returns (uint256) {
        if (epoch == 0) return SUPPLY_YEAR_0;
        
        // Determine which year this epoch falls into
        uint256 year = epoch / EPOCHS_PER_YEAR;
        
        // Start from the precomputed supply at the beginning of this year
        uint256 supply = _getSupplyAtYearBoundary(year);
        
        // Calculate the starting epoch for this year
        uint256 yearStartEpoch = year * EPOCHS_PER_YEAR;
        
        // Get the growth factor for this year
        uint256 growthFactor = _getGrowthFactorForYear(year);
        
        // Calculate how many epochs within the year we need to apply growth for
        uint256 epochsInYear = epoch - yearStartEpoch;
        
        if (epochsInYear == 0) {
            return supply;
        }
        
        // Calculate: supply * (growthFactor ^ epochsInYear)
        // PRBMath pow() expects both base and exponent in UD60x18 format (scaled by 1e18)
        UD60x18 supplyUD = ud(supply);
        UD60x18 factorUD = ud(growthFactor);
        UD60x18 epochsUD = ud(epochsInYear * SCALE); // Scale exponent by 1e18 for PRBMath
        
        // Calculate factor^epochs
        UD60x18 multiplierUD = pow(factorUD, epochsUD);
        
        // Apply to supply: supply * multiplier
        UD60x18 resultUD = supplyUD * multiplierUD / ud(SCALE);
        
        return unwrap(resultUD);
    }
    
    /// @notice Get precomputed supply at year boundary
    /// @param year The year number (0-indexed)
    /// @return The supply at the start of that year
    function _getSupplyAtYearBoundary(uint256 year) internal pure returns (uint256) {
        if (year == 0) return SUPPLY_YEAR_0;
        if (year == 1) return SUPPLY_YEAR_1;
        if (year == 2) return SUPPLY_YEAR_2;
        if (year == 3) return SUPPLY_YEAR_3;
        if (year == 4) return SUPPLY_YEAR_4;
        if (year == 5) return SUPPLY_YEAR_5;
        if (year == 6) return SUPPLY_YEAR_6;
        if (year == 7) return SUPPLY_YEAR_7;
        if (year == 8) return SUPPLY_YEAR_8;
        if (year == 9) return SUPPLY_YEAR_9;
        
        // For year 10+, calculate from year 9 using PRBMath
        // This should rarely happen in practice
        uint256 supply = SUPPLY_YEAR_9;
        uint256 yearsToCalculate = year - 9;
        
        // Use PRBMath to calculate: supply * (FINAL_R_PER_EPOCH ^ (yearsToCalculate * EPOCHS_PER_YEAR))
        UD60x18 supplyUD = ud(supply);
        UD60x18 factorUD = ud(FINAL_R_PER_EPOCH);
        UD60x18 totalEpochsUD = ud(yearsToCalculate * EPOCHS_PER_YEAR * SCALE); // Scale exponent
        
        // Calculate factor^totalEpochs
        UD60x18 multiplierUD = pow(factorUD, totalEpochsUD);
        
        // Apply to supply: supply * multiplier
        UD60x18 resultUD = supplyUD * multiplierUD / ud(SCALE);
        
        return unwrap(resultUD);
    }
    
    /// @notice Get growth factor for a specific year
    /// @param year The year number (0-indexed)
    /// @return The per-epoch growth factor for that year
    function _getGrowthFactorForYear(uint256 year) internal pure returns (uint256) {
        if (year == 0) return Y0_R_PER_EPOCH;
        if (year == 1) return Y1_R_PER_EPOCH;
        if (year == 2) return Y2_R_PER_EPOCH;
        if (year == 3) return Y3_R_PER_EPOCH;
        if (year == 4) return Y4_R_PER_EPOCH;
        if (year == 5) return Y5_R_PER_EPOCH;
        if (year == 6) return Y6_R_PER_EPOCH;
        if (year == 7) return Y7_R_PER_EPOCH;
        
        // Year 8 and beyond use the minimum rate
        return FINAL_R_PER_EPOCH;
    }
    
    /// @notice Returns the amount of ZKC that will be emitted at the end of the provided epoch.
    /// @param epoch The epoch number
    /// @return The amount of new tokens to be emitted at the end of this epoch
    function getEmissionsForEpoch(uint256 epoch) internal returns (uint256) {
        // TODO: Possible repeated work, both between these calls, 
        // and during batch claims of consecutive epochs.

        uint256 supplyAtNextEpoch = _getCachedEpochSupply(epoch + 1);
        if (supplyAtNextEpoch == 0) {
            supplyAtNextEpoch = getSupplyAtEpoch(epoch + 1);
            _cacheEpochSupply(epoch + 1, supplyAtNextEpoch);
        }
        
        uint256 supplyAtEpoch = _getCachedEpochSupply(epoch);
        if (supplyAtEpoch == 0) {
            supplyAtEpoch = getSupplyAtEpoch(epoch);
            _cacheEpochSupply(epoch, supplyAtEpoch);
        }
        
        return supplyAtNextEpoch - supplyAtEpoch;
    }

    /// @notice Get which year a given epoch falls into
    /// @param epoch The epoch number (0-indexed)
    /// @return The year number (0-indexed)
    function getYearForEpoch(uint256 epoch) internal pure returns (uint256) {
        return epoch / EPOCHS_PER_YEAR;
    }

    // Supply values for epochs are cached, to enable efficient batch claims of epochs.
    // This is a transient storage cache, so it is not persisted across blocks.
    // Note we do not need to clear the cache after use, as supply values are deterministic.
    
    // Apply a prefix to reduce risk of collisions with future tstore features. 
    // Leaves 20 bytes for epoch (max epoch: 2^160 - 1).
    bytes32 private constant CACHE_PREFIX = 0x5A4B43454D495353494F4E530000000000000000000000000000000000000000;

    /// @notice Calculate transient storage slot for epoch supply cache
    /// @param epoch The epoch number to cache
    /// @return slot The transient storage slot
    function _getSupplyCacheSlot(uint256 epoch) private pure returns (bytes32 slot) {
        assembly {
            slot := or(CACHE_PREFIX, epoch)
        }
    }

    function _cacheEpochSupply(uint256 epoch, uint256 supply) internal {
        bytes32 slot = _getSupplyCacheSlot(epoch);
        assembly {
            tstore(slot, supply)
        }
    }

    function _getCachedEpochSupply(uint256 epoch) internal view returns (uint256 supply) {
        bytes32 slot = _getSupplyCacheSlot(epoch);
        assembly {
            supply := tload(slot)
        }
    }
    
    
    
}