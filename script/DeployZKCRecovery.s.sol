// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ZKCRecovery} from "../src/ZKCRecovery.sol";

/**
 * Deploys the ZKCRecovery implementation only. It does not touch ZKC or the Safe.
 * Build the Safe transaction afterwards with script/RecoverZKC.s.sol.
 *
 * forge script script/DeployZKCRecovery.s.sol:DeployZKCRecovery --rpc-url $MAINNET_RPC_URL --account <keystore> --broadcast
 */
contract DeployZKCRecovery is Script {
    function run() public returns (address recoveryImpl) {
        vm.startBroadcast();
        recoveryImpl = address(new ZKCRecovery());
        vm.stopBroadcast();

        console2.log("ZKCRecovery impl:", recoveryImpl);
        console2.log("  recipient:", ZKCRecovery(recoveryImpl).RECOVERY_RECIPIENT());
        console2.log("  amount:", ZKCRecovery(recoveryImpl).RECOVERY_AMOUNT());
    }
}
