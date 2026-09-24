// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ZKCRecovery} from "../src/ZKCRecovery.sol";

/**
 * Deploys ZKCRecovery (if ZKC_RECOVERY_IMPL is unset) and prints the calls to batch in a single
 * Safe transaction from the ZKC admin Safe:
 *   1. ZKC.upgradeToAndCall(ZKCRecovery, recoverSelfTransfer())
 *   2. ZKC.upgradeToAndCall(PREV_IMPL, "")
 *
 * forge script script/RecoverZKC.s.sol:RecoverZKC --rpc-url <RPC_URL> --broadcast --private-key <DEPLOYER_KEY>
 */
contract RecoverZKC is Script {
    address constant ZKC = 0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555;
    address constant PREV_IMPL = 0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98;
    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() public {
        require(address(uint160(uint256(vm.load(ZKC, IMPL_SLOT)))) == PREV_IMPL, "unexpected current ZKC impl");

        address recoveryImpl = vm.envOr("ZKC_RECOVERY_IMPL", address(0));
        if (recoveryImpl == address(0)) {
            vm.startBroadcast();
            recoveryImpl = address(new ZKCRecovery());
            vm.stopBroadcast();
        }

        bytes memory call1 = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", recoveryImpl, abi.encodeCall(ZKCRecovery.recoverSelfTransfer, ())
        );
        bytes memory call2 = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", PREV_IMPL, "");

        console2.log("ZKCRecovery impl:", recoveryImpl);
        console2.log("=== Safe batch (both calls: to = ZKC, value = 0) ===");
        console2.log("ZKC:", ZKC);
        console2.log("Call 1: upgradeToAndCall(ZKCRecovery, recoverSelfTransfer())");
        console2.log("  recipient:", ZKCRecovery(recoveryImpl).RECOVERY_RECIPIENT());
        console2.log("  amount:", ZKCRecovery(recoveryImpl).RECOVERY_AMOUNT());
        console2.logBytes(call1);
        console2.log("Call 2: upgradeToAndCall(prevImpl, 0x)");
        console2.logBytes(call2);
        console2.log("Expected events: Upgraded(ZKCRecovery), Transfer(ZKC -> recipient, amount), Upgraded(prevImpl)");
    }
}
