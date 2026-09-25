// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ZKCRecovery} from "../src/ZKCRecovery.sol";

interface ISafe {
    function nonce() external view returns (uint256);
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
}

/// @notice Single source of truth for the recovery Safe transaction, shared by the script and fork test.
library RecoverZKCCalldata {
    address internal constant ZKC = 0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555;
    address internal constant PREV_IMPL = 0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98;
    /// @dev ZKC admin Safe (v1.4.1)
    address internal constant SAFE = 0x3886eEaf95AA2bDDdf0C924925e290291f70447F;
    /// @dev Safe v1.4.1 canonical MultiSendCallOnly
    address internal constant MULTISEND_CALL_ONLY = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function call1(address recoveryImpl) internal pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", recoveryImpl, abi.encodeCall(ZKCRecovery.recoverSelfTransfer, ())
        );
    }

    function call2() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("upgradeToAndCall(address,bytes)", PREV_IMPL, "");
    }

    function _pack(bytes memory data) private pure returns (bytes memory) {
        // operation (0 = CALL), to, value, data length, data
        return abi.encodePacked(uint8(0), ZKC, uint256(0), uint256(data.length), data);
    }

    /// @notice Calldata for the Safe tx: to = MULTISEND_CALL_ONLY, operation = 1 (DELEGATECALL), value = 0
    function multiSendData(address recoveryImpl) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("multiSend(bytes)", abi.encodePacked(_pack(call1(recoveryImpl)), _pack(call2())));
    }
}

/**
 * Deploys ZKCRecovery (if ZKC_RECOVERY_IMPL is unset) and prints the single Safe transaction for the
 * ZKC admin Safe (MultiSendCallOnly delegatecall batching both calls to ZKC):
 *   1. ZKC.upgradeToAndCall(ZKCRecovery, recoverSelfTransfer())
 *   2. ZKC.upgradeToAndCall(PREV_IMPL, "")
 *
 * Deploy:  forge script script/RecoverZKC.s.sol:RecoverZKC --rpc-url $MAINNET_RPC_URL --account <keystore> --broadcast --verify
 * Print:   ZKC_RECOVERY_IMPL=<addr> forge script script/RecoverZKC.s.sol:RecoverZKC --rpc-url $MAINNET_RPC_URL
 */
contract RecoverZKC is Script {
    function run() public {
        address zkc = RecoverZKCCalldata.ZKC;
        require(
            address(uint160(uint256(vm.load(zkc, RecoverZKCCalldata.IMPL_SLOT)))) == RecoverZKCCalldata.PREV_IMPL,
            "unexpected current ZKC impl"
        );

        address recoveryImpl = vm.envOr("ZKC_RECOVERY_IMPL", address(0));
        if (recoveryImpl == address(0)) {
            vm.startBroadcast();
            recoveryImpl = address(new ZKCRecovery());
            vm.stopBroadcast();
        }
        require(recoveryImpl.code.length > 0, "ZKC_RECOVERY_IMPL has no code");

        bytes memory data = RecoverZKCCalldata.multiSendData(recoveryImpl);
        ISafe safe = ISafe(RecoverZKCCalldata.SAFE);
        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = safe.getTransactionHash(
            RecoverZKCCalldata.MULTISEND_CALL_ONLY, 0, data, 1, 0, 0, 0, address(0), address(0), nonce
        );

        console2.log("ZKCRecovery impl:", recoveryImpl);
        console2.log("  recipient:", ZKCRecovery(recoveryImpl).RECOVERY_RECIPIENT());
        console2.log("  amount:", ZKCRecovery(recoveryImpl).RECOVERY_AMOUNT());
        console2.log("");
        console2.log("=== Individual calls (to = ZKC, value = 0) ===");
        console2.log("ZKC:", zkc);
        console2.log("Call 1: upgradeToAndCall(ZKCRecovery, recoverSelfTransfer())");
        console2.logBytes(RecoverZKCCalldata.call1(recoveryImpl));
        console2.log("Call 2: upgradeToAndCall(prevImpl, 0x)");
        console2.logBytes(RecoverZKCCalldata.call2());
        console2.log("");
        console2.log("=== Safe transaction ===");
        console2.log("safe:", RecoverZKCCalldata.SAFE);
        console2.log("to (MultiSendCallOnly v1.4.1):", RecoverZKCCalldata.MULTISEND_CALL_ONLY);
        console2.log(
            "value: 0, operation: 1 (DELEGATECALL), safeTxGas/baseGas/gasPrice: 0, gasToken/refundReceiver: 0x0"
        );
        console2.log("nonce:", nonce);
        console2.log("data:");
        console2.logBytes(data);
        console2.log("safeTxHash:");
        console2.logBytes32(safeTxHash);
        console2.log("");
        console2.log("Expected events: Upgraded(ZKCRecovery), Transfer(ZKC -> recipient, amount), Upgraded(prevImpl)");
    }
}
