// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {UpgradeZKC} from "../script/Upgrade.s.sol";

import {SafeFork} from "./SafeFork.sol";
import {ZKC, PoVWSunset} from "../src/ZKC.sol";
import {veZKC} from "../src/veZKC.sol";
import {StakingRewards} from "../src/rewards/StakingRewards.sol";
import {SupplyCalculator} from "../src/calculators/SupplyCalculator.sol";

contract ZKCForkTest is SafeFork {
    ZKC constant token = ZKC(0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555);
    veZKC constant staking = veZKC(0xE8Ae8eE8ffa57F6a79B6Cbe06BAFc0b05F3ffbf4);
    StakingRewards constant rewards = StakingRewards(0x459d87D54808faC136dDCF439fcc1D8a238311C7);
    SupplyCalculator constant calculator = SupplyCalculator(0x15eB8cA378E33381c867573EF2f25Ca1010f866d);
    address constant FOUNDATION = 0x3886eEaf95AA2bDDdf0C924925e290291f70447F;
    address constant STAKER = 0xade5C4b00Ab283608928c29e55917899DA8aC608;
    address constant POVW_MINTER = 0xBFCE7c2d5e7EdDEab71B3eeED770713c8b755397;
    address constant BASELINE = 0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98;
    address candidate;

    function setUp() public {
        assertEq(block.chainid, 1, "Ethereum fork required");
        assertEq(block.number, vm.envOr("SUNSET_BLOCK_NUMBER", uint256(26276732)), "pinned block required");
        assertEq(implementation(address(token)), BASELINE);
        assertEq(BASELINE.codehash, 0x809103882fcb7d3a50c452a7db932916ec00c50abacbb3452508085a6aa79529);
        assertEq(token.epoch0StartTime(), 1757536895);
        assertTrue(token.hasRole(token.ADMIN_ROLE(), FOUNDATION));
        assertTrue(token.hasRole(token.POVW_MINTER_ROLE(), POVW_MINTER));
        assertTrue(token.hasRole(token.STAKING_MINTER_ROLE(), address(rewards)));
        assertEq(staking.getActiveTokenId(STAKER), 1);
        (uint256 amount, uint256 withdrawableAt) = staking.getStakedAmountAndWithdrawalTime(STAKER);
        assertEq(amount, 10 ether);
        assertEq(withdrawableAt, 0);
        candidate = prepareCandidate(vm.envOr("SUNSET_IMPL", address(0)));
    }

    function upgrade() internal {
        uint256 supply = token.claimedTotalSupply();
        uint256 balance = token.balanceOf(STAKER);
        uint256 stakedBalance = token.balanceOf(address(staking));
        uint256 p = token.poVWClaimed();
        uint256 s = token.stakingClaimed();
        uint256 nonce = token.nonces(STAKER);
        vm.record();
        executeSafe(FOUNDATION, address(token), upgradeCall(candidate), 0);
        assertOnlyImplementationWritten(address(token));
        assertEq(implementation(address(token)), candidate);
        assertEq(token.claimedTotalSupply(), supply);
        assertEq(token.balanceOf(STAKER), balance);
        assertEq(token.balanceOf(address(staking)), stakedBalance);
        assertEq(token.poVWClaimed(), p);
        assertEq(token.stakingClaimed(), s);
        assertEq(token.nonces(STAKER), nonce);
        assertTrue(token.hasRole(token.POVW_MINTER_ROLE(), POVW_MINTER));
        assertTrue(token.hasRole(token.STAKING_MINTER_ROLE(), address(rewards)));
    }

    function testForkSafeUpgradeAndEmissionBoundaries() public {
        uint256[] memory epochs = new uint256[](6);
        epochs[0] = 181;
        epochs[1] = 182;
        epochs[2] = 209;
        epochs[3] = 210;
        epochs[4] = 211;
        epochs[5] = 364;
        uint256[] memory oldStaking = new uint256[](6);
        uint256[] memory oldCumulative = new uint256[](6);
        uint256[] memory oldPovw = new uint256[](6);
        uint256[] memory oldPovwCumulative = new uint256[](6);
        uint256 cap = token.getTotalPoVWEmissionsAtEpochStart(210);
        for (uint256 i; i < epochs.length; ++i) {
            oldPovw[i] = token.getPoVWEmissionsForEpoch(epochs[i]);
            oldPovwCumulative[i] = token.getTotalPoVWEmissionsAtEpochStart(epochs[i]);
            oldStaking[i] = token.getStakingEmissionsForEpoch(epochs[i]);
            oldCumulative[i] = token.getTotalStakingEmissionsAtEpochStart(epochs[i]);
        }
        upgrade();
        for (uint256 i; i < epochs.length; ++i) {
            assertEq(token.getStakingEmissionsForEpoch(epochs[i]), oldStaking[i]);
            assertEq(token.getTotalStakingEmissionsAtEpochStart(epochs[i]), oldCumulative[i]);
            if (epochs[i] < 210) {
                assertEq(token.getPoVWEmissionsForEpoch(epochs[i]), oldPovw[i]);
                assertEq(token.getTotalPoVWEmissionsAtEpochStart(epochs[i]), oldPovwCumulative[i]);
            } else {
                assertEq(token.getPoVWEmissionsForEpoch(epochs[i]), 0);
                assertEq(token.getTotalPoVWEmissionsAtEpochStart(epochs[i]), cap);
                assertEq(token.getSupplyAtEpochStart(epochs[i]), token.INITIAL_SUPPLY() + cap + oldCumulative[i]);
            }
        }
        vm.warp(T - 1);
        vm.prank(POVW_MINTER);
        token.mintPoVWRewardsForRecipient(STAKER, 1);
        uint256 claimed = token.poVWClaimed();
        for (uint256 i; i < 2; ++i) {
            vm.warp(T + i);
            vm.prank(POVW_MINTER);
            vm.expectRevert(PoVWSunset.selector);
            token.mintPoVWRewardsForRecipient(STAKER, 1);
            assertEq(token.poVWClaimed(), claimed);
        }
        assertEq(calculator.totalSupply(), token.totalSupply());
        assertEq(calculator.totalSupplyAtTimestamp(block.timestamp), token.totalSupply());
    }

    function claimAndWithdraw() internal returns (uint256 reward, uint256 principal) {
        vm.warp(T + 6 days);
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = 209;
        epochs[1] = 212;
        vm.prank(STAKER);
        reward = rewards.claimRewards(epochs);
        assertGt(reward, 0, "existing holder must receive rewards");
        vm.prank(STAKER);
        staking.initiateUnstake();
        vm.warp(T + 36 days - 1);
        vm.prank(STAKER);
        vm.expectRevert();
        staking.completeUnstake();
        vm.warp(T + 36 days);
        uint256 beforeBalance = token.balanceOf(STAKER);
        vm.prank(STAKER);
        staking.completeUnstake();
        principal = token.balanceOf(STAKER) - beforeBalance;
        assertEq(principal, 10 ether);
    }

    function testForkExistingHolderClaimsAndWithdrawalsMatchOriginal() public {
        // Normalize delegation using ordinary holder calls on both sides of the comparison.
        vm.startPrank(STAKER);
        staking.delegate(STAKER);
        staking.delegateRewards(STAKER);
        vm.stopPrank();
        uint256 snapshot = vm.snapshotState();
        (uint256 expectedReward, uint256 expectedPrincipal) = claimAndWithdraw();
        assertTrue(vm.revertToState(snapshot));
        upgrade();
        (uint256 actualReward, uint256 actualPrincipal) = claimAndWithdraw();
        assertEq(actualReward, expectedReward);
        assertEq(actualPrincipal, expectedPrincipal);
    }

    function testForkPendingWithdrawalSurvivesUpgrade() public {
        vm.startPrank(STAKER);
        staking.delegate(STAKER);
        staking.delegateRewards(STAKER);
        staking.initiateUnstake();
        vm.stopPrank();
        uint256 start = block.timestamp;
        upgrade();
        vm.warp(start + 30 days);
        uint256 balance = token.balanceOf(STAKER);
        vm.prank(STAKER);
        staking.completeUnstake();
        assertEq(token.balanceOf(STAKER) - balance, 10 ether);
    }

    function testForkUnauthorizedUpgradeAndLocalRollback() public {
        bytes memory unauthorized = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, STAKER, token.ADMIN_ROLE()
        );
        vm.prank(STAKER);
        vm.expectRevert(unauthorized);
        token.upgradeToAndCall(candidate, "");
        assertEq(implementation(address(token)), BASELINE);
        upgrade();
        vm.prank(STAKER);
        vm.expectRevert(unauthorized);
        token.upgradeToAndCall(BASELINE, "");
        assertEq(implementation(address(token)), candidate);
        vm.prank(FOUNDATION);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initializeV3();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initializeV2();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize(address(1), address(2), 0, 0, FOUNDATION);
        ZKC replacement = ZKC(candidate);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        replacement.initialize(address(1), address(2), 0, 0, FOUNDATION);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        replacement.initializeV2();
        vm.prank(FOUNDATION);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        replacement.initializeV3();
        uint256 balance = token.balanceOf(STAKER);
        executeSafe(FOUNDATION, address(token), abi.encodeCall(token.upgradeToAndCall, (BASELINE, bytes(""))), 0);
        assertEq(implementation(address(token)), BASELINE);
        assertEq(token.balanceOf(STAKER), balance);
        executeSafe(FOUNDATION, address(token), upgradeCall(candidate), 0);
        assertEq(implementation(address(token)), candidate);
    }

    function prepareCandidate(address requested) internal returns (address result) {
        if (requested != address(0)) {
            requireExisting(requested);
            address expectedImplementation = address(new ZKC());
            checkRuntime(
                expectedImplementation,
                requested,
                string.concat(vm.projectRoot(), "/", vm.envString("SUNSET_ARTIFACT_ROOT"), "/ZKC.sol/ZKC.json")
            );
            return requested;
        }
        vm.setEnv("CHAIN_KEY", "ethereum-mainnet");
        vm.setEnv("STACK_TAG", "");
        vm.setEnv("GNOSIS_EXECUTE", "true");
        // OZ validation runs separately; this suite exercises deployment and the real Safe.
        vm.setEnv("SKIP_SAFETY_CHECKS", "true");
        string memory config = vm.readFile("deployment.toml");
        address local = new UpgradeZKC().run();
        assertEq(vm.readFile("deployment.toml"), config, "preparation changed deployment config");
        assertEq(implementation(address(token)), BASELINE, "preparation upgraded proxy");
        result = requested == address(0) ? local : requested;
        checkRuntime(
            local,
            result,
            string.concat(vm.projectRoot(), "/", vm.envString("SUNSET_ARTIFACT_ROOT"), "/ZKC.sol/ZKC.json")
        );
    }

    function checkCandidate(address value) external {
        prepareCandidate(value);
    }

    function testForkCandidateRuntimeValidation() public {
        this.checkCandidate(candidate);
        vm.expectRevert(abi.encodeWithSelector(RuntimeMismatch.selector, BASELINE));
        this.checkCandidate(BASELINE);
        vm.expectRevert(abi.encodeWithSelector(RuntimeMismatch.selector, address(1)));
        this.checkCandidate(address(1));
    }

    function checkUndeployedReferenceAddress() external {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        assertEq(predicted.code.length, 0);
        prepareCandidate(predicted);
    }

    function testForkRejectsUndeployedReferenceAddress() public {
        vm.expectPartialRevert(RuntimeMismatch.selector);
        this.checkUndeployedReferenceAddress();
    }
}
