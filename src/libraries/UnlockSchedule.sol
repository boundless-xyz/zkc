// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Supply} from "./Supply.sol";

/// @title Genesis allocation unlock schedule
/// @notice Step function of cumulative unlocked ZKC from the initial 1B supply.
/// @dev PoVW and staking emissions are not in this table. They enter circulating
///      supply through claimedTotalSupply.
library UnlockSchedule {
    uint256 internal constant CLIFF_COUNT = 28;

    function unlockedAt(uint256 timestamp) internal pure returns (uint256) {
        uint256[28] memory cliffs = _cliffs();
        if (timestamp < cliffs[0]) {
            return 0;
        }
        uint256 i = CLIFF_COUNT - 1;
        while (timestamp < cliffs[i]) {
            unchecked {
                --i;
            }
        }
        return _cumulativeUnlocked()[i];
    }

    function lockedAt(uint256 timestamp) internal pure returns (uint256) {
        return Supply.INITIAL_SUPPLY - unlockedAt(timestamp);
    }

    /// @dev Unix timestamps (00:00:00 UTC on the 15th) at which `unlocked` steps up.
    ///      Not amounts. Index `i` here is the same index as `_cumulativeUnlocked()[i]`.
    function _cliffs() private pure returns (uint256[28] memory) {
        return [
            uint256(1757894400), // 2025-09-15 TGE
            1760486400, // 2025-10-15 1M
            1773532800, // 2026-03-15 6M
            1789430400, // 2026-09-15 12M=1Y
            1792022400, // 2026-10-15 13M
            1794700800, // 2026-11-15 14M
            1797292800, // 2026-12-15 15M
            1799971200, // 2027-01-15 16M
            1802649600, // 2027-02-15 17M
            1805068800, // 2027-03-15 18M
            1807747200, // 2027-04-15 19M
            1810339200, // 2027-05-15 20M
            1813017600, // 2027-06-15 21M
            1815609600, // 2027-07-15 22M
            1818288000, // 2027-08-15 23M
            1820966400, // 2027-09-15 24M=2Y
            1823558400, // 2027-10-15 25M
            1826236800, // 2027-11-15 26M
            1828828800, // 2027-12-15 27M
            1831507200, // 2028-01-15 28M
            1834185600, // 2028-02-15 29M
            1836691200, // 2028-03-15 30M
            1839369600, // 2028-04-15 31M
            1841961600, // 2028-05-15 32M
            1844640000, // 2028-06-15 33M
            1847232000, // 2028-07-15 34M
            1849910400, // 2028-08-15 35M
            1852588800 // 2028-09-15 36M=3Y
        ];
    }

    /// @dev Cumulative genesis ZKC unlocked as of cliff `i`, not the monthly delta.
    ///      After cliff `i`, `unlockedAt` returns this value until the next cliff.
    ///      Excludes epoch emissions (PoVW and staking). Those are minted over time
    ///      and show up in claimedTotalSupply, not here.
    function _cumulativeUnlocked() private pure returns (uint256[28] memory) {
        return [
            uint256(200953107000000000000000000), // 200,953,107 ZKC
            205453107000000000000000000, // 205,453,107 ZKC
            253286190000000000000000000, // 253,286,190 ZKC
            471464643000000000000000000, // 471,464,643 ZKC
            490861950000000000000000000, // 490,861,950 ZKC
            510259257000000000000000000, // 510,259,257 ZKC
            529656564000000000000000000, // 529,656,564 ZKC
            549053871000000000000000000, // 549,053,871 ZKC
            568451178000000000000000000, // 568,451,178 ZKC
            587848485000000000000000000, // 587,848,485 ZKC
            607245792000000000000000000, // 607,245,792 ZKC
            626643099000000000000000000, // 626,643,099 ZKC
            646040406000000000000000000, // 646,040,406 ZKC
            665437713000000000000000000, // 665,437,713 ZKC
            684835020000000000000000000, // 684,835,020 ZKC
            767232327000000000000000000, // 767,232,327 ZKC
            786629634000000000000000000, // 786,629,634 ZKC
            806026940000000000000000000, // 806,026,940 ZKC
            825424246000000000000000000, // 825,424,246 ZKC
            844821552000000000000000000, // 844,821,552 ZKC
            864218858000000000000000000, // 864,218,858 ZKC
            883616164000000000000000000, // 883,616,164 ZKC
            903013470000000000000000000, // 903,013,470 ZKC
            922410776000000000000000000, // 922,410,776 ZKC
            941808082000000000000000000, // 941,808,082 ZKC
            961205388000000000000000000, // 961,205,388 ZKC
            980602694000000000000000000, // 980,602,694 ZKC
            1000000000000000000000000000 // 1,000,000,000 ZKC
        ];
    }
}
