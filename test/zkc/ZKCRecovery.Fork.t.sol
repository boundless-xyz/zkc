// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ZKC} from "../../src/ZKC.sol";
import {ZKCRecovery} from "../../src/ZKCRecovery.sol";

/// @notice Mainnet fork test for the upgrade -> recover -> rollback flow.
/// @dev Run with: MAINNET_RPC_URL=<url> forge test --match-contract ZKCRecoveryForkTest
contract ZKCRecoveryForkTest is Test {
    ZKC constant zkc = ZKC(0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555);
    address constant SAFE = 0x3886eEaf95AA2bDDdf0C924925e290291f70447F;
    address constant PREV_IMPL = 0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98;

    // Tx 0xb4d0876ba9c719d56daae809c51f6553a5936f87674f2ed588e6c32d860997f3
    address constant RECIPIENT = 0x51DEf0949495956a5a177087C930AbB7171104c0;
    uint256 constant AMOUNT = 1_290_546e18;

    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    ZKCRecovery recoveryImpl;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        recoveryImpl = new ZKCRecovery();
    }

    function _impl() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(zkc), IMPL_SLOT))));
    }

    function test_recoverAndRollback() public {
        assertEq(_impl(), PREV_IMPL);
        assertEq(recoveryImpl.RECOVERY_RECIPIENT(), RECIPIENT);
        assertEq(recoveryImpl.RECOVERY_AMOUNT(), AMOUNT);

        // Snapshot state that must be untouched
        uint256 totalSupply = zkc.totalSupply();
        uint256 claimed = zkc.claimedTotalSupply();
        uint256 epoch0 = zkc.epoch0StartTime();
        uint256 povwClaimed = zkc.poVWClaimed();
        uint256 stakingClaimed = zkc.stakingClaimed();
        address minter1 = zkc.initialMinter1();
        address minter2 = zkc.initialMinter2();
        uint256 m1Remaining = zkc.initialMinter1Remaining();
        uint256 m2Remaining = zkc.initialMinter2Remaining();
        uint256 epoch = zkc.getCurrentEpoch();
        uint256 selfBal = zkc.balanceOf(address(zkc));
        uint256 recipientBal = zkc.balanceOf(RECIPIENT);

        // Exactly what the Safe will batch via MultiSend
        vm.expectEmit(true, true, false, true, address(zkc));
        emit IERC20.Transfer(address(zkc), RECIPIENT, AMOUNT);
        vm.startPrank(SAFE);
        zkc.upgradeToAndCall(address(recoveryImpl), abi.encodeCall(ZKCRecovery.recoverSelfTransfer, ()));
        zkc.upgradeToAndCall(PREV_IMPL, "");
        vm.stopPrank();

        assertEq(_impl(), PREV_IMPL);
        assertEq(zkc.balanceOf(RECIPIENT), recipientBal + AMOUNT);
        assertEq(zkc.balanceOf(address(zkc)), selfBal - AMOUNT);

        assertEq(zkc.totalSupply(), totalSupply);
        assertEq(zkc.claimedTotalSupply(), claimed);
        assertEq(zkc.epoch0StartTime(), epoch0);
        assertEq(zkc.poVWClaimed(), povwClaimed);
        assertEq(zkc.stakingClaimed(), stakingClaimed);
        assertEq(zkc.initialMinter1(), minter1);
        assertEq(zkc.initialMinter2(), minter2);
        assertEq(zkc.initialMinter1Remaining(), m1Remaining);
        assertEq(zkc.initialMinter2Remaining(), m2Remaining);
        assertEq(zkc.getCurrentEpoch(), epoch);
        assertTrue(zkc.hasRole(zkc.ADMIN_ROLE(), SAFE));

        // Recovery function is gone after rollback
        vm.prank(SAFE);
        vm.expectRevert();
        ZKCRecovery(address(zkc)).recoverSelfTransfer();
    }

    function test_recoverSelfTransfer_onlyAdmin() public {
        vm.prank(SAFE);
        zkc.upgradeToAndCall(address(recoveryImpl), "");

        address attacker = makeAddr("attacker");
        bytes32 adminRole = zkc.ADMIN_ROLE();
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, adminRole)
        );
        ZKCRecovery(address(zkc)).recoverSelfTransfer();
    }
}
