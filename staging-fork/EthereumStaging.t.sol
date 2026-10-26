// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IForkSafe} from "./SafeFork.sol";
import {StagingSafeFork} from "./StagingSafeFork.sol";
import {ZKC, PoVWSunset} from "../src/ZKC.sol";
import {veZKC} from "../src/veZKC.sol";
import {StakingRewards} from "../src/rewards/StakingRewards.sol";

interface IStagePovw {
    function owner() external view returns (address);
    function pendingEpoch() external view returns (uint96 totalWork, uint256 number);
    function finalizeEpoch() external;
    function updateWorkLog(address, bytes32, uint64, address, bytes calldata) external;
    function mint(bytes calldata, bytes calldata) external;
    function upgradeToAndCall(address, bytes calldata) external payable;
    function initialize(address) external;
}

contract StagingEthereumForkTest is StagingSafeFork {
    ZKC internal token;
    veZKC internal staking;
    StakingRewards internal rewards;
    address internal accounting;
    address internal minter;
    address internal user;
    address[3] internal proxies;
    address[3] internal candidates;
    address[3] internal baselines;
    uint256 internal cutoffEpoch;
    uint256 internal duration;
    uint256 internal constant AMOUNT = 10 ether;
    address constant MULTISEND = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
    bytes4 constant STOP = bytes4(keccak256("ProtocolSunset()"));

    function setUp() public {
        assertEq(block.chainid, 11155111);
        loadStagingBundle();
        accounting = address(bytes20(hex"129aeab812d77c102ff1ad9d76dfb55faae4b8d3"));
        minter = address(bytes20(hex"8c2a4a28116ed8b8fe559bc53e30b6a056c5d3c9"));
        token = ZKC(address(bytes20(hex"99a52662b576f4b2d4ffbc4504331a624a7b2846")));
        staking = veZKC(address(bytes20(hex"b7c63161da06ec56840465308e24c70df65abc56")));
        rewards = StakingRewards(address(bytes20(hex"881fe38501d869bdb8d747a3506562c73413cabe")));
        proxies = [accounting, minter, address(token)];
        assertEq(bundleTarget, MULTISEND);
        assertEq(bundleOperation, 1);
        assertEq(MULTISEND.codehash, 0xa9865ac2d9c7a1591619b188c4d88167b50df6cc0c5327fcbd1c8c75f7c066ad);
        for (uint256 i; i < 3; ++i) {
            candidates[i] = checkStage(i, proxies[i]);
            baselines[i] = stageAddress(i, "baseline");
        }
        assertEq(bundleData, packedUpgrade(candidates));
        assertEq(IStagePovw(accounting).owner(), stagingSafe);
        assertEq(IStagePovw(minter).owner(), stagingSafe);
        assertTrue(token.hasRole(token.ADMIN_ROLE(), stagingSafe));
        assertTrue(token.hasRole(token.POVW_MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.STAKING_MINTER_ROLE(), address(rewards)));
        assertEq(address(rewards.zkc()), address(token));
        assertEq(address(rewards.veZKC()), address(staking));
        duration = token.EPOCH_DURATION();
        cutoffEpoch = (T - token.epoch0StartTime()) / duration;
        user = vm.addr(0xabc123);
        // Seed only the local holder fixture; use deployed staking and rewards contracts unchanged.
        deal(address(token), user, AMOUNT);
        vm.startPrank(user);
        token.approve(address(staking), AMOUNT);
        staking.stake(AMOUNT);
        staking.delegate(user);
        staking.delegateRewards(user);
        vm.stopPrank();
    }

    function packedUpgrade(address[3] memory implementations) internal view returns (bytes memory) {
        bytes memory packed;
        for (uint256 i; i < 3; ++i) {
            bytes memory call =
                abi.encodeWithSignature("upgradeToAndCall(address,bytes)", implementations[i], bytes(""));
            packed = abi.encodePacked(packed, uint8(0), proxies[i], uint256(0), uint256(call.length), call);
        }
        return abi.encodeWithSignature("multiSend(bytes)", packed);
    }

    function stateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                token.claimedTotalSupply(),
                token.poVWClaimed(),
                token.stakingClaimed(),
                token.balanceOf(user),
                token.balanceOf(address(staking)),
                token.nonces(user),
                IStagePovw(accounting).owner(),
                IStagePovw(minter).owner()
            )
        );
    }

    function upgrade() internal {
        bytes32 state = stateHash();
        (uint96 work, uint256 epoch) = IStagePovw(accounting).pendingEpoch();
        vm.record();
        executeBundle();
        for (uint256 i; i < 3; ++i) {
            assertEq(implementation(proxies[i]), candidates[i]);
            assertOnlyImplementationWritten(proxies[i]);
        }
        assertEq(stateHash(), state);
        (uint96 afterWork, uint256 afterEpoch) = IStagePovw(accounting).pendingEpoch();
        assertEq(afterWork, work);
        assertEq(afterEpoch, epoch);
        assertTrue(token.hasRole(token.ADMIN_ROLE(), stagingSafe));
        assertTrue(token.hasRole(token.POVW_MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.STAKING_MINTER_ROLE(), address(rewards)));
    }

    function testStageExactAtomicBatchAndCutoff() public {
        upgrade();
        vm.warp(T - 1);
        IStagePovw(accounting).finalizeEpoch();
        vm.prank(minter);
        token.mintPoVWRewardsForRecipient(user, 1);
        uint256 claimed = token.poVWClaimed();
        for (uint256 i; i < 3; ++i) {
            vm.warp(T + (i == 2 ? duration : i));
            vm.expectRevert(STOP);
            IStagePovw(accounting).finalizeEpoch();
            vm.expectRevert(STOP);
            IStagePovw(accounting).updateWorkLog(user, bytes32(0), 0, user, "");
            vm.expectRevert(STOP);
            IStagePovw(minter).mint("", "");
            vm.prank(minter);
            vm.expectRevert(PoVWSunset.selector);
            token.mintPoVWRewardsForRecipient(user, 0);
            assertEq(token.poVWClaimed(), claimed);
        }
    }

    function testStageSupplyAndStakingCurves() public {
        uint256[5] memory epochs = [cutoffEpoch - 1, cutoffEpoch, cutoffEpoch + 1, cutoffEpoch + 52, cutoffEpoch + 156];
        uint256[5] memory stakingEpoch;
        uint256[5] memory stakingTotal;
        uint256 oldPastPovw = token.getTotalPoVWEmissionsAtEpochStart(cutoffEpoch - 1);
        uint256 cap = token.getTotalPoVWEmissionsAtEpochStart(cutoffEpoch);
        for (uint256 i; i < 5; ++i) {
            stakingEpoch[i] = token.getStakingEmissionsForEpoch(epochs[i]);
            stakingTotal[i] = token.getTotalStakingEmissionsAtEpochStart(epochs[i]);
        }
        upgrade();
        assertEq(token.getTotalPoVWEmissionsAtEpochStart(cutoffEpoch - 1), oldPastPovw);
        for (uint256 i; i < 5; ++i) {
            assertEq(token.getStakingEmissionsForEpoch(epochs[i]), stakingEpoch[i]);
            assertEq(token.getTotalStakingEmissionsAtEpochStart(epochs[i]), stakingTotal[i]);
            if (epochs[i] >= cutoffEpoch) {
                assertEq(token.getPoVWEmissionsForEpoch(epochs[i]), 0);
                assertEq(token.getTotalPoVWEmissionsAtEpochStart(epochs[i]), cap);
                assertEq(token.getSupplyAtEpochStart(epochs[i]), token.INITIAL_SUPPLY() + cap + stakingTotal[i]);
            }
        }
        vm.warp(T + duration);
        uint256 supply = token.totalSupply();
        vm.warp(T + 2 * duration);
        assertGt(token.totalSupply(), supply, "passive staking inflation must continue");
    }

    function claimAndWithdraw() internal returns (uint256 reward, uint256 principal) {
        vm.warp(T + 3 * duration);
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = cutoffEpoch - 1;
        epochs[1] = cutoffEpoch + 1;
        vm.prank(user);
        reward = rewards.claimRewards(epochs);
        assertGt(reward, 0);
        vm.prank(user);
        staking.initiateUnstake();
        (, uint256 ready) = staking.getStakedAmountAndWithdrawalTime(user);
        assertEq(ready, block.timestamp + 30 days);
        vm.warp(ready - 1);
        vm.prank(user);
        vm.expectRevert(bytes4(keccak256("WithdrawalPeriodNotComplete()")));
        staking.completeUnstake();
        vm.warp(ready);
        uint256 beforeBalance = token.balanceOf(user);
        vm.prank(user);
        staking.completeUnstake();
        principal = token.balanceOf(user) - beforeBalance;
        assertEq(principal, AMOUNT);
    }

    function testStageRewardsAndWithdrawalsMatchOriginal() public {
        uint256 snapshot = vm.snapshotState();
        (uint256 expectedReward, uint256 expectedPrincipal) = claimAndWithdraw();
        assertTrue(vm.revertToState(snapshot));
        upgrade();
        (uint256 actualReward, uint256 actualPrincipal) = claimAndWithdraw();
        assertEq(actualReward, expectedReward);
        assertEq(actualPrincipal, expectedPrincipal);
    }

    function testStagePendingWithdrawalSurvivesUpgrade() public {
        vm.prank(user);
        staking.initiateUnstake();
        (, uint256 ready) = staking.getStakedAmountAndWithdrawalTime(user);
        upgrade();
        vm.warp(ready);
        uint256 balance = token.balanceOf(user);
        vm.prank(user);
        staking.completeUnstake();
        assertEq(token.balanceOf(user) - balance, AMOUNT);
    }

    function testStageFailedThirdUpgradeIsAtomic() public {
        address[3] memory failed = candidates;
        failed[2] = address(0);
        bytes32 state = stateHash();
        vm.expectCall(proxies[0], abi.encodeWithSignature("upgradeToAndCall(address,bytes)", candidates[0], bytes("")));
        vm.expectCall(proxies[1], abi.encodeWithSignature("upgradeToAndCall(address,bytes)", candidates[1], bytes("")));
        vm.expectCall(proxies[2], abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(0), bytes("")));
        uint256 nonce = IForkSafe(stagingSafe).nonce();
        vm.expectRevert(bytes("GS013"));
        this.executeInvalidBatch(packedUpgrade(failed));
        assertEq(IForkSafe(stagingSafe).nonce(), nonce);
        for (uint256 i; i < 3; ++i) {
            assertEq(implementation(proxies[i]), baselines[i]);
        }
        assertEq(stateHash(), state);
    }

    function executeInvalidBatch(bytes calldata data) external {
        executeStaging(bundleTarget, data, 1, true);
    }

    function testStageUnauthorizedAndInitializers() public {
        for (uint256 i; i < 2; ++i) {
            vm.prank(user);
            vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
            IStagePovw(proxies[i]).upgradeToAndCall(candidates[i], "");
        }
        bytes memory unauthorized =
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.ADMIN_ROLE());
        vm.prank(user);
        vm.expectRevert(unauthorized);
        token.upgradeToAndCall(candidates[2], "");
        upgrade();
        for (uint256 i; i < 2; ++i) {
            vm.prank(user);
            vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
            IStagePovw(proxies[i]).upgradeToAndCall(baselines[i], "");
            vm.expectRevert(Initializable.InvalidInitialization.selector);
            IStagePovw(proxies[i]).initialize(user);
            vm.expectRevert(Initializable.InvalidInitialization.selector);
            IStagePovw(candidates[i]).initialize(user);
        }
        vm.prank(user);
        vm.expectRevert(unauthorized);
        token.upgradeToAndCall(baselines[2], "");
    }

    function testStageReinitializerBehaviorMatchesOriginal() public {
        bytes[2] memory calls = [abi.encodeCall(token.initializeV2, ()), abi.encodeCall(token.initializeV3, ())];
        bool[2] memory success;
        bytes[2] memory returned;
        for (uint256 i; i < 2; ++i) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(stagingSafe);
            (success[i], returned[i]) = address(token).call(calls[i]);
            assertTrue(vm.revertToState(snapshot));
        }
        upgrade();
        for (uint256 i; i < 2; ++i) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(stagingSafe);
            (bool ok, bytes memory data) = address(token).call(calls[i]);
            assertEq(ok, success[i]);
            assertEq(data, returned[i]);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    function testStageRollbackAllThree() public {
        upgrade();
        bytes32 state = stateHash();
        executeStaging(bundleTarget, packedUpgrade(baselines), 1, true);
        for (uint256 i; i < 3; ++i) {
            assertEq(implementation(proxies[i]), baselines[i]);
        }
        assertEq(stateHash(), state);
        executeBundle();
        for (uint256 i; i < 3; ++i) {
            assertEq(implementation(proxies[i]), candidates[i]);
        }
    }
}
