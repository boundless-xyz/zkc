// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {UnlockSchedule} from "../../src/libraries/UnlockSchedule.sol";
import {Supply} from "../../src/libraries/Supply.sol";

contract UnlockScheduleTest is Test {
    uint256 internal constant TGE = 1757894400; // 2025-09-15
    uint256 internal constant CLIFF_6M = 1773532800; // 2026-03-15
    uint256 internal constant CLIFF_12M = 1789430400; // 2026-09-15
    uint256 internal constant CLIFF_13M = 1792022400; // 2026-10-15
    uint256 internal constant CLIFF_24M = 1820966400; // 2027-09-15
    uint256 internal constant CLIFF_26M = 1826236800; // 2027-11-15
    uint256 internal constant CLIFF_36M = 1852588800; // 2028-09-15

    uint256 internal constant UNLOCKED_6M = 253_286_190e18;
    uint256 internal constant UNLOCKED_12M = 471_464_643e18;
    uint256 internal constant UNLOCKED_13M = 490_861_950e18;
    uint256 internal constant UNLOCKED_24M = 767_232_327e18;
    uint256 internal constant UNLOCKED_26M = 806_026_940e18;

    function testBeforeTge() public pure {
        assertEq(UnlockSchedule.unlockedAt(TGE - 1), 0);
        assertEq(UnlockSchedule.lockedAt(TGE - 1), Supply.INITIAL_SUPPLY);
    }

    function testAt6MCliff() public pure {
        assertEq(UnlockSchedule.unlockedAt(CLIFF_6M), UNLOCKED_6M);
        assertEq(UnlockSchedule.lockedAt(CLIFF_6M), Supply.INITIAL_SUPPLY - UNLOCKED_6M);
    }

    function testOneSecondBefore12MCliff() public pure {
        assertEq(UnlockSchedule.unlockedAt(CLIFF_12M - 1), UNLOCKED_6M);
    }

    function testAt12MCliff() public pure {
        assertEq(UnlockSchedule.unlockedAt(CLIFF_12M), UNLOCKED_12M);
    }

    function testAt13MCliff() public pure {
        assertEq(UnlockSchedule.unlockedAt(CLIFF_13M), UNLOCKED_13M);
    }

    function testAt24MCliff() public pure {
        assertEq(UnlockSchedule.unlockedAt(CLIFF_24M), UNLOCKED_24M);
    }

    function testAt26MCliff() public pure {
        assertEq(UnlockSchedule.unlockedAt(CLIFF_26M), UNLOCKED_26M);
    }

    function testAt36MCliffAndAfter() public pure {
        assertEq(UnlockSchedule.unlockedAt(CLIFF_36M), Supply.INITIAL_SUPPLY);
        assertEq(UnlockSchedule.unlockedAt(CLIFF_36M + 365 days), Supply.INITIAL_SUPPLY);
        assertEq(UnlockSchedule.lockedAt(CLIFF_36M), 0);
    }

    function testLockedPlusUnlockedEqualsInitialSupply() public pure {
        uint256[6] memory timestamps = [uint256(TGE - 1), CLIFF_6M, CLIFF_12M, CLIFF_24M, CLIFF_26M, CLIFF_36M];

        for (uint256 i = 0; i < timestamps.length; ++i) {
            assertEq(
                UnlockSchedule.unlockedAt(timestamps[i]) + UnlockSchedule.lockedAt(timestamps[i]), Supply.INITIAL_SUPPLY
            );
        }
    }
}
