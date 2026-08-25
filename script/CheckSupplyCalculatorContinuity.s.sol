// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console2} from "forge-std/Script.sol";
import {SupplyCalculator} from "../src/calculators/SupplyCalculator.sol";
import {UnlockSchedule} from "../src/libraries/UnlockSchedule.sol";
import {ConfigLoader, DeploymentConfig} from "./Config.s.sol";
import {BaseDeployment} from "./BaseDeployment.s.sol";

/**
 * Compare live SupplyCalculator storage values to UnlockSchedule at the current
 * block timestamp. If they match, upgrading the implementation is a no-op for
 * unlocked / locked / circulating until the next cliff.
 *
 * CHAIN_KEY=ethereum-mainnet forge script \
 *     script/CheckSupplyCalculatorContinuity.s.sol:CheckSupplyCalculatorContinuity \
 *     --rpc-url <RPC_URL>
 */
contract CheckSupplyCalculatorContinuity is BaseDeployment {
    function run() public {
        (DeploymentConfig memory config,) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.supplyCalculator != address(0), "SupplyCalculator not deployed");

        SupplyCalculator live = SupplyCalculator(config.supplyCalculator);
        uint256 liveUnlocked = live.unlocked();
        uint256 liveLocked = live.locked();
        uint256 liveCirculating = live.circulatingSupply();

        uint256 scheduledUnlocked = UnlockSchedule.unlockedAt(block.timestamp);
        uint256 scheduledLocked = UnlockSchedule.lockedAt(block.timestamp);
        uint256 scheduledCirculating = live.claimedTotalSupply() - scheduledLocked;

        console2.log("block.timestamp", block.timestamp);
        console2.log("live unlocked", liveUnlocked);
        console2.log("scheduled unlocked", scheduledUnlocked);
        console2.log("live locked", liveLocked);
        console2.log("scheduled locked", scheduledLocked);
        console2.log("live circulating", liveCirculating);
        console2.log("scheduled circulating", scheduledCirculating);

        require(liveUnlocked == scheduledUnlocked, "unlocked mismatch");
        require(liveLocked == scheduledLocked, "locked mismatch");
        require(liveCirculating == scheduledCirculating, "circulating mismatch");

        console2.log("Live contract matches UnlockSchedule at this timestamp");
    }
}
