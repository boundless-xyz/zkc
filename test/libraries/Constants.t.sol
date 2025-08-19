// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract ConstantsTest is Test {
    function testRelationships() public pure {
        // Max should be greater than min
        assertGt(Constants.MAX_STAKE_TIME_S, Constants.MIN_STAKE_TIME_S);
        
        // Max should be divisible by week
        assertEq(Constants.MAX_STAKE_TIME_S % Constants.WEEK, 0);
        
        // Min should be divisible by week
        assertEq(Constants.MIN_STAKE_TIME_S % Constants.WEEK, 0);
        
        // iMAX should equal MAX
        assertEq(uint128(Constants.iMAX_STAKE_TIME_S), Constants.MAX_STAKE_TIME_S);
    }
}