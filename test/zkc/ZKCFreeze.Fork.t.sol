// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ZKC} from "../../src/ZKC.sol";
import {ZKCFreeze} from "../../src/ZKCFreeze.sol";

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

/// @notice Mainnet fork test for upgrading ZKC to ZKCFreeze and rolling back.
/// @dev Run with: MAINNET_RPC_URL=<url> forge test --match-contract ZKCFreezeForkTest
contract ZKCFreezeForkTest is Test {
    ZKC constant zkc = ZKC(0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555);
    address constant SAFE = 0x3886eEaf95AA2bDDdf0C924925e290291f70447F;
    address constant PREV_IMPL = 0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98;
    address constant STAKING_REWARDS = 0x459d87D54808faC136dDCF439fcc1D8a238311C7;
    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    ZKCFreeze impl;
    address frozen;
    address other = makeAddr("other");
    address spender = makeAddr("spender");

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        assertEq(_impl(), PREV_IMPL, "unexpected current ZKC impl");

        impl = new ZKCFreeze();
        frozen = impl.FROZEN();
        assertGt(zkc.balanceOf(frozen), 0, "frozen address has no balance");

        // Allowance granted before the freeze must not be spendable after it.
        vm.prank(frozen);
        zkc.approve(spender, type(uint256).max);
        deal(address(zkc), other, 1_000e18);

        _upgrade();
    }

    /// @dev Direct admin upgrade; test_safeExecTransaction covers the real Safe path.
    function _upgrade() internal {
        vm.prank(SAFE);
        zkc.upgradeToAndCall(address(impl), "");
        assertEq(_impl(), address(impl));
    }

    function test_debitsFromFrozenRevert() public {
        bytes memory err = abi.encodeWithSelector(ZKCFreeze.AccountFrozen.selector, frozen);

        vm.startPrank(frozen);
        vm.expectRevert(err);
        zkc.transfer(other, 1);
        vm.expectRevert(err);
        zkc.transfer(frozen, 1);
        vm.expectRevert(err);
        zkc.transfer(other, 0);
        vm.expectRevert(err);
        zkc.burn(1);
        vm.stopPrank();

        vm.startPrank(spender);
        vm.expectRevert(err);
        zkc.transferFrom(frozen, other, 1);
        vm.expectRevert(err);
        zkc.burnFrom(frozen, 1);
        vm.stopPrank();
    }

    function test_incomingAndUnrelatedTransfersWork() public {
        uint256 frozenBefore = zkc.balanceOf(frozen);
        uint256 supplyBefore = zkc.claimedTotalSupply();

        vm.prank(other);
        zkc.transfer(frozen, 10e18);
        assertEq(zkc.balanceOf(frozen), frozenBefore + 10e18);

        vm.prank(other);
        zkc.transfer(spender, 5e18);
        assertEq(zkc.balanceOf(spender), 5e18);

        vm.prank(other);
        zkc.burn(1e18);
        assertEq(zkc.claimedTotalSupply(), supplyBefore - 1e18);
    }

    function test_rewardMintToFrozenWorks() public {
        // A batch mint that includes the frozen address must not revert.
        vm.warp(zkc.getEpochEndTime(zkc.getCurrentEpoch()) + 1);
        uint256 before = zkc.balanceOf(frozen);
        vm.prank(STAKING_REWARDS);
        zkc.mintStakingRewardsForRecipient(frozen, 1);
        assertEq(zkc.balanceOf(frozen), before + 1);
    }

    function test_onlyAdminCanUpgrade() public {
        bytes32 adminRole = zkc.ADMIN_ROLE();
        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, adminRole)
        );
        zkc.upgradeToAndCall(PREV_IMPL, "");
    }

    function test_rollbackUnfreezes() public {
        vm.prank(SAFE);
        zkc.upgradeToAndCall(PREV_IMPL, "");
        assertEq(_impl(), PREV_IMPL);

        vm.prank(frozen);
        zkc.transfer(other, 1);
        vm.prank(spender);
        zkc.transferFrom(frozen, other, 1);
    }

    /// @notice Executes the Safe tx that UpgradeZKC (GNOSIS_EXECUTE) prints, via execTransaction.
    function test_safeExecTransaction() public {
        // Back to the pre-freeze state so the Safe tx starts from the live implementation.
        vm.prank(SAFE);
        zkc.upgradeToAndCall(PREV_IMPL, "");
        assertEq(_impl(), PREV_IMPL);

        ISafe safe = ISafe(SAFE);
        address[] memory owners = safe.getOwners();
        uint256 threshold = safe.getThreshold();
        assertEq(threshold, 3);
        uint256 nonce = safe.nonce();
        uint256 frozenBal = zkc.balanceOf(frozen);
        uint256 claimed = zkc.claimedTotalSupply();

        bytes memory data = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(impl), "");
        bytes32 txHash = safe.getTransactionHash(address(zkc), 0, data, 0, 0, 0, 0, address(0), address(0), nonce);

        // Pick `threshold` owners in ascending order and pre-approve the hash (v = 1 signatures)
        address[] memory signers = _sortedFirst(owners, threshold);
        bytes memory sigs;
        for (uint256 i = 0; i < signers.length; i++) {
            vm.prank(signers[i]);
            safe.approveHash(txHash);
            sigs = abi.encodePacked(sigs, bytes32(uint256(uint160(signers[i]))), bytes32(0), uint8(1));
        }

        vm.prank(signers[0]);
        assertTrue(safe.execTransaction(address(zkc), 0, data, 0, 0, 0, 0, address(0), payable(address(0)), sigs));

        assertEq(safe.nonce(), nonce + 1);
        assertEq(_impl(), address(impl));
        assertEq(zkc.balanceOf(frozen), frozenBal);
        assertEq(zkc.claimedTotalSupply(), claimed);
        assertTrue(zkc.hasRole(zkc.ADMIN_ROLE(), SAFE));

        vm.prank(frozen);
        vm.expectRevert(abi.encodeWithSelector(ZKCFreeze.AccountFrozen.selector, frozen));
        zkc.transfer(other, 1);
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

    function _impl() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(zkc), IMPL_SLOT))));
    }
}
