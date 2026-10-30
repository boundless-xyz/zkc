// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ZKC} from "../../src/ZKC.sol";
import {ZKCFreeze} from "../../src/ZKCFreeze.sol";

/// @notice Mainnet fork test for upgrading ZKC to ZKCFreeze and rolling back.
/// @dev Run with: MAINNET_RPC_URL=<url> forge test --match-contract ZKCFreezeForkTest
contract ZKCFreezeForkTest is Test {
    ZKC constant zkc = ZKC(0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555);
    address constant SAFE = 0x3886eEaf95AA2bDDdf0C924925e290291f70447F;
    address constant PREV_IMPL = 0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98;
    address constant STAKING_REWARDS = 0x459d87D54808faC136dDCF439fcc1D8a238311C7;
    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

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

        ZKCFreeze impl = new ZKCFreeze();
        frozen = impl.FROZEN();
        assertGt(zkc.balanceOf(frozen), 0, "frozen address has no balance");

        // Allowance granted before the freeze must not be spendable after it.
        vm.prank(frozen);
        zkc.approve(spender, type(uint256).max);
        deal(address(zkc), other, 1_000e18);

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

    function _impl() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(zkc), IMPL_SLOT))));
    }
}
