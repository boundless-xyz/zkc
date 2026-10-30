// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ZKC} from "../../src/ZKC.sol";
import {ZKCFreeze} from "../../src/ZKCFreeze.sol";
import {ZKCSweep} from "../../src/ZKCSweep.sol";
import {SweepZKCCalldata} from "../../script/SweepZKC.s.sol";

interface ISafe {
    function nonce() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function approveHash(bytes32 hashToApprove) external;
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
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool);
}

/// @notice Mainnet fork test for the ZKCFreeze -> ZKCSweep (sweep) -> ZKCFreeze flow.
/// @dev Run with: MAINNET_RPC_URL=<url> forge test --match-contract ZKCSweepForkTest
///      Set ZKC_SWEEP_IMPL=<addr> (with FOUNDRY_PROFILE=freeze) to test against the deployed ZKCSweep
///      instead of a fresh local deploy.
contract ZKCSweepForkTest is Test {
    ZKC constant zkc = ZKC(0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555);
    address constant SAFE = 0x3886eEaf95AA2bDDdf0C924925e290291f70447F;
    address constant FREEZE_IMPL = 0x5c13832f8833D50d4fCc3a1f985226525A44021C;
    /// @dev ZKC implementation live before ZKCFreeze, used to replay a genuine transfer() by FROZEN
    address constant PRE_FREEZE_IMPL = 0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98;
    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 constant UPGRADED = keccak256("Upgraded(address)");

    ZKCSweep sweepImpl;
    address frozen;
    address recipient;
    uint256 amount;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        assertEq(_impl(), FREEZE_IMPL, "unexpected current ZKC impl");

        ZKCSweep local = new ZKCSweep();
        address deployed = vm.envOr("ZKC_SWEEP_IMPL", address(0));
        if (deployed == address(0)) {
            sweepImpl = local;
        } else {
            // Deployed runtime code must match this build, modulo the UUPS __self immutable (its own address)
            assertEq(
                _replaceAddress(address(local).code, address(local), deployed), deployed.code, "deployed code mismatch"
            );
            sweepImpl = ZKCSweep(deployed);
        }

        frozen = sweepImpl.FROZEN();
        recipient = sweepImpl.SWEEP_RECIPIENT();
        amount = sweepImpl.SWEEP_AMOUNT();
        assertEq(frozen, ZKCFreeze(FREEZE_IMPL).FROZEN());
        assertGe(zkc.balanceOf(frozen), amount, "frozen balance below SWEEP_AMOUNT");
    }

    /// @notice Executes the exact Safe tx the script prints (MultiSendCallOnly delegatecall) via execTransaction
    function test_safeExecTransaction() public {
        ISafe safe = ISafe(SAFE);
        uint256 nonce = safe.nonce();
        uint256 frozenBal = zkc.balanceOf(frozen);
        uint256 recipientBal = zkc.balanceOf(recipient);

        // Snapshot state that must be untouched
        uint256 totalSupply = zkc.totalSupply();
        uint256 claimed = zkc.claimedTotalSupply();
        uint256 epoch0 = zkc.epoch0StartTime();
        uint256 povwClaimed = zkc.poVWClaimed();
        uint256 stakingClaimed = zkc.stakingClaimed();
        uint256 m1Remaining = zkc.initialMinter1Remaining();
        uint256 m2Remaining = zkc.initialMinter2Remaining();
        uint256 frozenNonce = zkc.nonces(frozen);

        bytes memory data = SweepZKCCalldata.multiSendData(address(sweepImpl));
        address to = SweepZKCCalldata.MULTISEND_CALL_ONLY;
        bytes memory sigs =
            _approve(safe, safe.getTransactionHash(to, 0, data, 1, 0, 0, 0, address(0), address(0), nonce));

        vm.recordLogs();
        vm.prank(_sortedFirst(safe.getOwners(), 1)[0]);
        assertTrue(safe.execTransaction(to, 0, data, 1, 0, 0, 0, address(0), payable(address(0)), sigs));

        // ZKC emits exactly: Upgraded(ZKCSweep), Transfer(FROZEN, recipient, amount), Upgraded(ZKCFreeze)
        Vm.Log[] memory logs = _logsFrom(vm.getRecordedLogs(), address(zkc));
        assertEq(logs.length, 3, "unexpected ZKC events");
        assertEq(logs[0].topics[0], UPGRADED);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(address(sweepImpl)))));
        assertEq(logs[1].topics[0], IERC20.Transfer.selector);
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(frozen))));
        assertEq(logs[1].topics[2], bytes32(uint256(uint160(recipient))));
        assertEq(abi.decode(logs[1].data, (uint256)), amount);
        assertEq(logs[2].topics[0], UPGRADED);
        assertEq(logs[2].topics[1], bytes32(uint256(uint160(FREEZE_IMPL))));

        assertEq(safe.nonce(), nonce + 1);
        assertEq(_impl(), FREEZE_IMPL);
        assertEq(zkc.balanceOf(frozen), frozenBal - amount);
        assertEq(zkc.balanceOf(recipient), recipientBal + amount);

        assertEq(zkc.totalSupply(), totalSupply);
        assertEq(zkc.claimedTotalSupply(), claimed);
        assertEq(zkc.epoch0StartTime(), epoch0);
        assertEq(zkc.poVWClaimed(), povwClaimed);
        assertEq(zkc.stakingClaimed(), stakingClaimed);
        assertEq(zkc.initialMinter1Remaining(), m1Remaining);
        assertEq(zkc.initialMinter2Remaining(), m2Remaining);
        assertEq(zkc.nonces(frozen), frozenNonce);
        assertTrue(zkc.hasRole(zkc.ADMIN_ROLE(), SAFE));

        // Sweep function is gone after rollback, and FROZEN stays frozen
        vm.prank(SAFE);
        vm.expectRevert();
        ZKCSweep(address(zkc)).sweep();
        vm.prank(frozen);
        vm.expectRevert(abi.encodeWithSelector(ZKCFreeze.AccountFrozen.selector, frozen));
        zkc.transfer(recipient, 0);

        // Recipient can move the swept tokens
        vm.prank(recipient);
        zkc.transfer(SAFE, amount);
    }

    /// @notice The sweep writes the same ZKC storage and emits the same events as FROZEN calling transfer()
    function test_sweepMatchesTransferByFrozen() public {
        uint256 snapshot = vm.snapshotState();

        // Genuine transfer() by FROZEN on the pre-freeze implementation
        vm.prank(SAFE);
        zkc.upgradeToAndCall(PRE_FREEZE_IMPL, "");
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(frozen);
        zkc.transfer(recipient, amount);
        bytes32[2][] memory transferWrites = _zkcWrites(vm.stopAndReturnStateDiff());
        Vm.Log[] memory transferLogs = _logsFrom(vm.getRecordedLogs(), address(zkc));

        vm.revertToState(snapshot);

        // Admin sweep, as batched by the Safe
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.startPrank(SAFE);
        zkc.upgradeToAndCall(address(sweepImpl), abi.encodeCall(ZKCSweep.sweep, ()));
        zkc.upgradeToAndCall(FREEZE_IMPL, "");
        vm.stopPrank();
        bytes32[2][] memory sweepWrites = _zkcWrites(vm.stopAndReturnStateDiff());
        Vm.Log[] memory sweepLogs = _logsFrom(vm.getRecordedLogs(), address(zkc));

        assertEq(sweepWrites.length, transferWrites.length, "storage write count");
        assertEq(sweepWrites.length, 2, "expected only the two balance slots");
        for (uint256 i = 0; i < sweepWrites.length; i++) {
            assertEq(sweepWrites[i][0], transferWrites[i][0], "slot");
            assertEq(sweepWrites[i][1], transferWrites[i][1], "value");
        }

        // Drop the two Upgraded events; the rest must be identical
        assertEq(transferLogs.length, 1);
        assertEq(sweepLogs.length, 3);
        assertEq(sweepLogs[1].topics, transferLogs[0].topics);
        assertEq(sweepLogs[1].data, transferLogs[0].data);
    }

    function test_sweep_onlyAdmin() public {
        vm.prank(SAFE);
        zkc.upgradeToAndCall(address(sweepImpl), "");

        address attacker = makeAddr("attacker");
        bytes32 adminRole = zkc.ADMIN_ROLE();
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, adminRole)
        );
        ZKCSweep(address(zkc)).sweep();
    }

    function test_freezeStillAppliesUnderSweepImpl() public {
        vm.prank(SAFE);
        zkc.upgradeToAndCall(address(sweepImpl), "");

        vm.prank(frozen);
        vm.expectRevert(abi.encodeWithSelector(ZKCFreeze.AccountFrozen.selector, frozen));
        zkc.transfer(recipient, 1);
    }

    function _approve(ISafe safe, bytes32 txHash) internal returns (bytes memory sigs) {
        // Pick `threshold` owners in ascending order and pre-approve the hash (v = 1 signatures)
        address[] memory signers = _sortedFirst(safe.getOwners(), safe.getThreshold());
        for (uint256 i = 0; i < signers.length; i++) {
            vm.prank(signers[i]);
            safe.approveHash(txHash);
            sigs = abi.encodePacked(sigs, bytes32(uint256(uint160(signers[i]))), bytes32(0), uint8(1));
        }
    }

    /// @dev Non-reverted ZKC storage writes as (slot, newValue), excluding the implementation slot
    function _zkcWrites(Vm.AccountAccess[] memory accesses) internal pure returns (bytes32[2][] memory out) {
        uint256 n;
        out = new bytes32[2][](64);
        for (uint256 i = 0; i < accesses.length; i++) {
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; j++) {
                Vm.StorageAccess memory s = accesses[i].storageAccesses[j];
                if (s.account != address(zkc) || !s.isWrite || s.reverted || s.slot == IMPL_SLOT) continue;
                out[n++] = [s.slot, s.newValue];
            }
        }
        assembly {
            mstore(out, n)
        }
    }

    function _logsFrom(Vm.Log[] memory logs, address emitter) internal pure returns (Vm.Log[] memory out) {
        uint256 n;
        out = new Vm.Log[](logs.length);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == emitter) out[n++] = logs[i];
        }
        assembly {
            mstore(out, n)
        }
    }

    function _sortedFirst(address[] memory a, uint256 n) internal pure returns (address[] memory out) {
        for (uint256 i = 0; i < a.length; i++) {
            for (uint256 j = i + 1; j < a.length; j++) {
                if (a[j] < a[i]) (a[i], a[j]) = (a[j], a[i]);
            }
        }
        out = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            out[i] = a[i];
        }
    }

    function _replaceAddress(bytes memory code, address from, address to) internal pure returns (bytes memory) {
        bytes20 f = bytes20(from);
        bytes20 t = bytes20(to);
        for (uint256 i = 0; i + 20 <= code.length; i++) {
            bytes20 w;
            assembly {
                w := mload(add(add(code, 32), i))
            }
            if (w == f) {
                for (uint256 j = 0; j < 20; j++) {
                    code[i + j] = t[j];
                }
                i += 19;
            }
        }
        return code;
    }

    function _impl() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(zkc), IMPL_SLOT))));
    }
}
