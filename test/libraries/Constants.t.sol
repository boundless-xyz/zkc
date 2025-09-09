// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract ConstantsTest is Test {
    function testWithdrawalPeriod() public pure {
        // Withdrawal period should be 30 days
        assertEq(Constants.WITHDRAWAL_PERIOD, 30 days);
        assertGt(Constants.WITHDRAWAL_PERIOD, 0);
    }

    function testPowerScalars() public pure {
        // Power scalars should be positive
        assertGt(Constants.VOTING_POWER_SCALAR, 0);
        assertGt(Constants.REWARD_POWER_SCALAR, 0);

        // Default scalars should be 1 for 1:1 ratio in token units
        assertEq(Constants.VOTING_POWER_SCALAR, 1);
        assertEq(Constants.REWARD_POWER_SCALAR, 1);
    }

    function testWeekConstant() public pure {
        // Week constant should equal 1 week
        assertEq(Constants.WEEK, 1 weeks);
        assertEq(Constants.WEEK, 7 days);
    }
}
