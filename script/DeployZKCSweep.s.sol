// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ZKCSweep} from "../src/ZKCSweep.sol";

/**
 * Deploys the ZKCSweep implementation only. It does not touch ZKC or the Safe.
 * Build the Safe transaction afterwards with script/SweepZKC.s.sol.
 *
 * Use the freeze profile so the runtime code carries no metadata hash, and do not verify the contract.
 *
 * FOUNDRY_PROFILE=freeze forge script script/DeployZKCSweep.s.sol:DeployZKCSweep --rpc-url $MAINNET_RPC_URL --account <keystore> --broadcast
 */
contract DeployZKCSweep is Script {
    function run() public returns (address sweepImpl) {
        vm.startBroadcast();
        sweepImpl = address(new ZKCSweep());
        vm.stopBroadcast();

        console2.log("ZKCSweep impl:", sweepImpl);
        console2.log("  source:", ZKCSweep(sweepImpl).FROZEN());
        console2.log("  recipient:", ZKCSweep(sweepImpl).SWEEP_RECIPIENT());
        console2.log("  amount:", ZKCSweep(sweepImpl).SWEEP_AMOUNT());
    }
}
