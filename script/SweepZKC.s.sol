// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ZKCSweep} from "../src/ZKCSweep.sol";

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

/// @notice Single source of truth for the sweep Safe transaction, shared by the script and fork test.
library SweepZKCCalldata {
    address internal constant ZKC = 0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555;
    /// @dev Live ZKCFreeze implementation the proxy is rolled back to
    address internal constant FREEZE_IMPL = 0x5c13832f8833D50d4fCc3a1f985226525A44021C;
    /// @dev ZKC admin Safe (v1.4.1)
    address internal constant SAFE = 0x3886eEaf95AA2bDDdf0C924925e290291f70447F;
    /// @dev Safe v1.4.1 canonical MultiSendCallOnly
    address internal constant MULTISEND_CALL_ONLY = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function call1(address sweepImpl) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("upgradeToAndCall(address,bytes)", sweepImpl, abi.encodeCall(ZKCSweep.sweep, ()));
    }

    function call2() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("upgradeToAndCall(address,bytes)", FREEZE_IMPL, "");
    }

    function _pack(bytes memory data) private pure returns (bytes memory) {
        // operation (0 = CALL), to, value, data length, data
        return abi.encodePacked(uint8(0), ZKC, uint256(0), uint256(data.length), data);
    }

    /// @notice Calldata for the Safe tx: to = MULTISEND_CALL_ONLY, operation = 1 (DELEGATECALL), value = 0
    function multiSendData(address sweepImpl) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("multiSend(bytes)", abi.encodePacked(_pack(call1(sweepImpl)), _pack(call2())));
    }
}

/**
 * Read-only: prints the single Safe transaction for the ZKC admin Safe (MultiSendCallOnly delegatecall
 * batching both calls to ZKC) for an already deployed ZKCSweep. Never broadcasts.
 *   1. ZKC.upgradeToAndCall(ZKCSweep, sweep())
 *   2. ZKC.upgradeToAndCall(FREEZE_IMPL, "")
 *
 * ZKC_SWEEP_IMPL=<addr> forge script script/SweepZKC.s.sol:SweepZKC --rpc-url $MAINNET_RPC_URL
 */
contract SweepZKC is Script {
    function run() public view {
        address zkc = SweepZKCCalldata.ZKC;
        require(block.chainid == 1, "not on Ethereum mainnet: pass --rpc-url <mainnet RPC>");
        require(zkc.code.length > 0, "ZKC has no code: RPC is not a mainnet node");
        require(
            address(uint160(uint256(vm.load(zkc, SweepZKCCalldata.IMPL_SLOT)))) == SweepZKCCalldata.FREEZE_IMPL,
            "unexpected current ZKC impl"
        );

        address sweepImpl = vm.envAddress("ZKC_SWEEP_IMPL");
        require(sweepImpl.code.length > 0, "ZKC_SWEEP_IMPL has no code");
        ZKCSweep sweep = ZKCSweep(sweepImpl);
        require(ZKCSweep(zkc).balanceOf(sweep.FROZEN()) >= sweep.SWEEP_AMOUNT(), "frozen balance below SWEEP_AMOUNT");

        bytes memory data = SweepZKCCalldata.multiSendData(sweepImpl);
        ISafe safe = ISafe(SweepZKCCalldata.SAFE);
        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = safe.getTransactionHash(
            SweepZKCCalldata.MULTISEND_CALL_ONLY, 0, data, 1, 0, 0, 0, address(0), address(0), nonce
        );

        console2.log("ZKCSweep impl:", sweepImpl);
        console2.log("  source:", sweep.FROZEN());
        console2.log("  recipient:", sweep.SWEEP_RECIPIENT());
        console2.log("  amount:", sweep.SWEEP_AMOUNT());
        console2.log("");
        console2.log("=== Individual calls (to = ZKC, value = 0) ===");
        console2.log("ZKC:", zkc);
        console2.log("Call 1: upgradeToAndCall(ZKCSweep, sweep())");
        console2.logBytes(SweepZKCCalldata.call1(sweepImpl));
        console2.log("Call 2: upgradeToAndCall(ZKCFreeze, 0x)");
        console2.logBytes(SweepZKCCalldata.call2());
        console2.log("");
        console2.log("=== Safe transaction ===");
        console2.log("safe:", SweepZKCCalldata.SAFE);
        console2.log("to (MultiSendCallOnly v1.4.1):", SweepZKCCalldata.MULTISEND_CALL_ONLY);
        console2.log(
            "value: 0, operation: 1 (DELEGATECALL), safeTxGas/baseGas/gasPrice: 0, gasToken/refundReceiver: 0x0"
        );
        console2.log("nonce:", nonce);
        console2.log("data:");
        console2.logBytes(data);
        console2.log("safeTxHash:");
        console2.logBytes32(safeTxHash);
        console2.log("");
        console2.log("Expected events: Upgraded(ZKCSweep), Transfer(FROZEN -> recipient, amount), Upgraded(ZKCFreeze)");
    }
}
