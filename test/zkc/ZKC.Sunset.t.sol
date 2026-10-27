// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ZKC, PoVWSunset} from "../../src/ZKC.sol";
import {IZKC} from "../../src/interfaces/IZKC.sol";
import {ZKCOriginal} from "../reference/ZKCOriginal.sol";
import {veZKC} from "../../src/veZKC.sol";
import {StakingRewards} from "../../src/rewards/StakingRewards.sol";
import {SupplyCalculator} from "../../src/calculators/SupplyCalculator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ZKCSunsetTest is Test {
    uint256 constant T = 1793836800;
    uint256 constant START = 1757536895;
    uint256 constant CUTOFF_EPOCH = 210;
    address owner = makeAddr("owner");
    address user;
    uint256 constant USER_KEY = 0xbeef;
    address minter = makeAddr("minter");
    ZKC token;
    ZKC original;
    veZKC stake;
    veZKC originalStake;
    StakingRewards rewards;
    StakingRewards originalRewards;

    function setUp() public {
        user = vm.addr(USER_KEY);
        vm.warp(START);
        (token, stake, rewards) = deploySystem();
        (original, originalStake, originalRewards) = deploySystem();
        vm.warp(START + 1);
        vm.startPrank(user);
        token.approve(address(stake), type(uint256).max);
        original.approve(address(originalStake), type(uint256).max);
        stake.stake(1_000_000 ether);
        originalStake.stake(1_000_000 ether);
        vm.stopPrank();
    }

    function deploySystem() internal returns (ZKC t, veZKC v, StakingRewards r) {
        ZKCOriginal implementation = new ZKCOriginal();
        t = ZKC(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(ZKCOriginal.initialize, (minter, address(0x1002), 1_000_000_000 ether, 0, owner))
                )
            )
        );
        vm.startPrank(owner);
        t.initializeV2();
        t.initializeV3();
        v = veZKC(
            address(new ERC1967Proxy(address(new veZKC()), abi.encodeCall(veZKC.initialize, (address(t), owner))))
        );
        r = StakingRewards(
            address(
                new ERC1967Proxy(
                    address(new StakingRewards()),
                    abi.encodeCall(StakingRewards.initialize, (address(t), address(v), owner))
                )
            )
        );
        t.grantRole(t.POVW_MINTER_ROLE(), minter);
        t.grantRole(t.STAKING_MINTER_ROLE(), address(r));
        vm.stopPrank();
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user;
        amounts[0] = 1_000_000_000 ether;
        vm.prank(minter);
        t.initialMint(recipients, amounts);
    }

    function upgrade() internal {
        ZKC implementation = new ZKC();
        vm.prank(owner);
        token.upgradeToAndCall(address(implementation), "");
    }

    function testUpgradePreservesStateAndPreCutoffBehavior() public {
        vm.warp(T - 1);
        vm.prank(minter);
        token.mintPoVWRewardsForRecipient(user, 10 ether);
        uint256 balance = token.balanceOf(user);
        uint256 supply = token.claimedTotalSupply();
        uint256 allowance = token.allowance(user, address(stake));
        uint256 theoretical = token.totalSupply();
        upgrade();
        assertEq(token.balanceOf(user), balance);
        assertEq(token.claimedTotalSupply(), supply);
        assertEq(token.totalSupply(), theoretical);
        assertEq(token.allowance(user, address(stake)), allowance);
        assertEq(token.nonces(user), 0);
        assertEq(token.epoch0StartTime(), START);
        assertEq(token.poVWClaimed(), 10 ether);
        assertTrue(token.hasRole(token.POVW_MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.STAKING_MINTER_ROLE(), address(rewards)));
        vm.prank(minter);
        token.mintPoVWRewardsForRecipient(user, 1 ether);
        assertEq(token.poVWClaimed(), 11 ether);
    }

    function testPoVWMintsRevertAtAndAfterCutoffEvenForOldBudgetOrZeroAmount() public {
        upgrade();
        vm.warp(T - 1);
        vm.prank(minter);
        token.mintPoVWRewardsForRecipient(user, 1 ether);
        uint256 claimed = token.poVWClaimed();
        for (uint256 i; i < 2; ++i) {
            vm.warp(T + i);
            vm.startPrank(minter);
            vm.expectRevert(PoVWSunset.selector);
            token.mintPoVWRewardsForRecipient(user, 1 ether);
            vm.expectRevert(PoVWSunset.selector);
            token.mintPoVWRewardsForRecipient(user, 0);
            vm.stopPrank();
            assertEq(token.poVWClaimed(), claimed);
        }
    }

    function testFuzzStakingAndSupplyCurve(uint16 rawEpoch) public {
        uint256 epoch = bound(uint256(rawEpoch), 0, 5000);
        upgrade();
        uint256 expectedPoVW = original.getTotalPoVWEmissionsAtEpochStart(epoch > CUTOFF_EPOCH ? CUTOFF_EPOCH : epoch);
        assertEq(token.getTotalPoVWEmissionsAtEpochStart(epoch), expectedPoVW);
        assertEq(
            token.getTotalStakingEmissionsAtEpochStart(epoch), original.getTotalStakingEmissionsAtEpochStart(epoch)
        );
        assertEq(token.getStakingEmissionsForEpoch(epoch), original.getStakingEmissionsForEpoch(epoch));
        assertEq(
            token.getPoVWEmissionsForEpoch(epoch), epoch < CUTOFF_EPOCH ? original.getPoVWEmissionsForEpoch(epoch) : 0
        );
        assertEq(
            token.getSupplyAtEpochStart(epoch),
            token.INITIAL_SUPPLY() + expectedPoVW + original.getTotalStakingEmissionsAtEpochStart(epoch)
        );
        assertEq(
            token.getEmissionsForEpoch(epoch),
            token.getPoVWEmissionsForEpoch(epoch) + original.getStakingEmissionsForEpoch(epoch)
        );
        if (epoch <= CUTOFF_EPOCH) assertEq(token.getSupplyAtEpochStart(epoch), original.getSupplyAtEpochStart(epoch));
    }

    function testRealOldAndNewStakingClaimsRemainIdentical() public {
        upgrade();
        vm.warp(T + 10 days);
        uint256[] memory epochs = new uint256[](4);
        epochs[0] = 181;
        epochs[1] = 182;
        epochs[2] = 209;
        epochs[3] = 212;
        vm.prank(user);
        uint256 expected = originalRewards.claimRewards(epochs);
        vm.prank(user);
        uint256 actual = rewards.claimRewards(epochs);
        assertGt(actual, 0);
        assertEq(actual, expected);
        assertEq(token.stakingClaimed(), original.stakingClaimed());
        assertEq(token.balanceOf(user), original.balanceOf(user));
    }

    function testWithdrawalInitiatedBeforeCutoffCompletesAfterUpgrade() public {
        vm.warp(T - 2 days);
        initiateBoth();
        upgrade();
        vm.warp(T + 30 days);
        completeBoth();
    }

    function testWithdrawalInitiatedAfterCutoffRemainsIdentical() public {
        upgrade();
        vm.warp(T);
        initiateBoth();
        vm.warp(T + 30 days);
        completeBoth();
    }

    function initiateBoth() internal {
        vm.startPrank(user);
        stake.initiateUnstake();
        originalStake.initiateUnstake();
        vm.stopPrank();
    }

    function completeBoth() internal {
        uint256 beforeBalance = token.balanceOf(user);
        vm.startPrank(user);
        stake.completeUnstake();
        originalStake.completeUnstake();
        vm.stopPrank();
        assertEq(token.balanceOf(user) - beforeBalance, 1_000_000 ether);
        assertEq(token.balanceOf(user), original.balanceOf(user));
    }

    function testSupplyCalculatorAndPostCutoffGrowth() public {
        upgrade();
        SupplyCalculator c = SupplyCalculator(
            address(
                new ERC1967Proxy(
                    address(new SupplyCalculator()),
                    abi.encodeCall(SupplyCalculator.initialize, (address(token), 0, owner))
                )
            )
        );
        vm.warp(T);
        uint256 budget = token.getTotalPoVWEmissionsAtEpochStart(token.getCurrentEpoch());
        uint256 supply = token.totalSupply();
        uint256 stakingBudget = token.getTotalStakingEmissionsAtEpochStart(token.getCurrentEpoch());
        vm.warp(T + 365 days);
        assertEq(c.totalSupply(), token.totalSupply());
        assertEq(c.totalSupplyAtTimestamp(block.timestamp), token.totalSupply());
        assertEq(token.getTotalPoVWEmissionsAtEpochStart(token.getCurrentEpoch()), budget);
        assertEq(
            token.totalSupply() - supply,
            token.getTotalStakingEmissionsAtEpochStart(token.getCurrentEpoch()) - stakingBudget
        );
        assertEq(c.claimedTotalSupply(), token.claimedTotalSupply());
    }

    function testUnauthorizedUpgradeAndReinitializationRejected() public {
        ZKC implementation = new ZKC();
        bytes32 adminRole = token.ADMIN_ROLE();
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, adminRole)
        );
        token.upgradeToAndCall(address(implementation), "");
        upgrade();
        vm.prank(owner);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initializeV3();
    }

    function testDeterministicEpochAndYearBoundaries() public {
        upgrade();
        for (uint256 year; year <= 12; ++year) {
            uint256 boundary = year * 182;
            for (uint256 offset; offset < 3; ++offset) {
                uint256 epoch = boundary + offset;
                if (boundary > 0) epoch -= 1;
                assertEq(
                    token.getTotalStakingEmissionsAtEpochStart(epoch),
                    original.getTotalStakingEmissionsAtEpochStart(epoch)
                );
                assertEq(token.getStakingEmissionsForEpoch(epoch), original.getStakingEmissionsForEpoch(epoch));
            }
        }
        assertGt(token.getPoVWEmissionsForEpoch(209), 0);
        assertEq(token.getPoVWEmissionsForEpoch(210), 0);
        assertEq(token.getPoVWEmissionsForEpoch(211), 0);
        assertEq(token.getTotalPoVWEmissionsAtEpochStart(210), token.getTotalPoVWEmissionsAtEpochStart(211));
    }

    function testOriginalTransientCachePrimedBeforeUpgrade() public {
        uint256 expectedStaking = original.getStakingEmissionsForEpoch(211);
        token.getEmissionsForEpoch(211);
        token.getEmissionsForEpoch(212);
        upgrade();
        assertEq(token.getPoVWEmissionsForEpoch(211), 0);
        assertEq(token.getEmissionsForEpoch(211), expectedStaking);
        assertEq(token.getStakingEmissionsForEpoch(212), original.getStakingEmissionsForEpoch(212));
    }

    function permitToken(ZKC t) internal {
        uint256 deadline = T + 1 days;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                user,
                address(0xcafe),
                100 ether,
                t.nonces(user),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", t.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 sigS) = vm.sign(USER_KEY, digest);
        t.permit(user, address(0xcafe), 100 ether, deadline, v, r, sigS);
    }

    function testNonzeroPermitNonceTransfersAndBurnsSurviveUpgrade() public {
        permitToken(token);
        permitToken(original);
        upgrade();
        vm.warp(T);
        assertEq(token.nonces(user), 1);
        assertEq(token.allowance(user, address(0xcafe)), 100 ether);
        vm.startPrank(address(0xcafe));
        token.transferFrom(user, address(0x1234), 10 ether);
        original.transferFrom(user, address(0x1234), 10 ether);
        vm.stopPrank();
        vm.startPrank(user);
        token.transfer(address(0x1234), 5 ether);
        original.transfer(address(0x1234), 5 ether);
        token.burn(20 ether);
        original.burn(20 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(user), original.balanceOf(user));
        assertEq(token.balanceOf(address(0x1234)), original.balanceOf(address(0x1234)));
        assertEq(token.claimedTotalSupply(), original.claimedTotalSupply());
    }

    function testDelegationAndThirtyDayWithdrawalBoundaryUnchanged() public {
        vm.prank(user);
        stake.delegateRewards(address(0xcafe));
        upgrade();
        vm.warp(T);
        vm.startPrank(user);
        vm.expectRevert();
        stake.initiateUnstake();
        stake.delegateRewards(user);
        stake.initiateUnstake();
        vm.warp(T + 30 days - 1);
        vm.expectRevert();
        stake.completeUnstake();
        vm.warp(T + 30 days);
        uint256 beforeBalance = token.balanceOf(user);
        stake.completeUnstake();
        vm.stopPrank();
        assertEq(token.balanceOf(user) - beforeBalance, 1_000_000 ether);
    }

    function testPriorClaimsStayClaimedAfterUpgrade() public {
        vm.warp(START + 5 days);
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 1;
        vm.prank(user);
        uint256 expected = originalRewards.claimRewards(epochs);
        vm.prank(user);
        assertEq(rewards.claimRewards(epochs), expected);
        uint256 claimed = token.stakingClaimed();
        upgrade();
        vm.warp(T + 3 days);
        assertEq(token.stakingClaimed(), claimed);
        vm.prank(user);
        vm.expectRevert();
        rewards.claimRewards(epochs);
        epochs[0] = 210;
        vm.prank(user);
        expected = originalRewards.claimRewards(epochs);
        vm.prank(user);
        assertEq(rewards.claimRewards(epochs), expected);
    }

    function testUnstartedEpochsRetainOriginalSupplyReporting() public {
        token = ZKC(
            address(
                new ERC1967Proxy(
                    address(new ZKC()),
                    abi.encodeCall(ZKC.initialize, (minter, address(0x1002), 1_000_000_000 ether, 0, owner))
                )
            )
        );
        assertEq(token.epoch0StartTime(), 0);
        assertEq(token.getSupplyAtEpochStart(300), original.getSupplyAtEpochStart(300));
        vm.prank(owner);
        token.initializeV2();
        assertEq(token.epoch0StartTime(), type(uint256).max);
        assertEq(token.getSupplyAtEpochStart(300), original.getSupplyAtEpochStart(300));
    }

    function testEpochsStartingAtOrAfterCutoffHaveNoPoVWBudget() public {
        for (uint256 i; i < 2; ++i) {
            vm.warp(T + i);
            (token,,) = deploySystem();
            upgrade();
            assertEq(token.getTotalPoVWEmissionsAtEpochStart(300), 0);
            assertEq(token.getPoVWEmissionsForEpoch(0), 0);
            assertEq(token.getStakingEmissionsForEpoch(300), original.getStakingEmissionsForEpoch(300));
        }
    }

    function testFullAvailablePoVWBudgetCanBeMintedUntilCutoff() public {
        upgrade();
        vm.warp(T - 1);
        uint256 budget = token.getTotalPoVWEmissionsAtEpochStart(token.getCurrentEpoch());
        vm.startPrank(minter);
        token.mintPoVWRewardsForRecipient(user, budget);
        vm.expectRevert();
        token.mintPoVWRewardsForRecipient(user, 1);
        vm.warp(T);
        vm.expectRevert(PoVWSunset.selector);
        token.mintPoVWRewardsForRecipient(user, 0);
        vm.stopPrank();
        assertEq(token.poVWClaimed(), budget);
    }

    function testFuzzCutoffWithDifferentEpochStarts(uint16 rawCutoffEpoch, uint32 rawOffset, uint16 rawEpoch) public {
        uint256 cutoffEpoch = bound(uint256(rawCutoffEpoch), 0, 5000);
        uint256 offset = bound(uint256(rawOffset), 0, 2 days - 1);
        uint256 epoch = bound(uint256(rawEpoch), 0, 10000);
        checkCutoffForEpochStart(T - cutoffEpoch * 2 days - offset, cutoffEpoch, epoch);
    }

    function testCutoffOnEpochBoundaryAndOneSecondEitherSide() public {
        for (uint256 i; i < 3; ++i) {
            checkCutoffForEpochStart(T - CUTOFF_EPOCH * 2 days - 1 + i, i == 2 ? 209 : 210, 210);
        }
    }

    function checkCutoffForEpochStart(uint256 start, uint256 cutoffEpoch, uint256 epoch) internal {
        vm.warp(start);
        (token,,) = deploySystem();
        upgrade();

        uint256 cappedEpoch = epoch < cutoffEpoch ? epoch : cutoffEpoch;
        assertEq(
            token.getTotalPoVWEmissionsAtEpochStart(epoch), original.getTotalPoVWEmissionsAtEpochStart(cappedEpoch)
        );
        assertEq(
            token.getPoVWEmissionsForEpoch(epoch), epoch < cutoffEpoch ? original.getPoVWEmissionsForEpoch(epoch) : 0
        );
        assertEq(token.getStakingEmissionsForEpoch(epoch), original.getStakingEmissionsForEpoch(epoch));
        assertEq(
            token.getSupplyAtEpochStart(epoch),
            original.INITIAL_SUPPLY() + original.getTotalPoVWEmissionsAtEpochStart(cappedEpoch)
                + original.getTotalStakingEmissionsAtEpochStart(epoch)
        );
        if (start < T) {
            vm.warp(T - 1);
            uint256 budget = original.getTotalPoVWEmissionsAtEpochStart(token.getCurrentEpoch());
            vm.prank(minter);
            token.mintPoVWRewardsForRecipient(user, budget);
            assertEq(token.poVWClaimed(), budget);
        }
        vm.warp(T);
        assertEq(token.getCurrentEpoch(), cutoffEpoch);
        assertEq(token.getPoVWEmissionsForEpoch(cutoffEpoch), 0);
        vm.prank(minter);
        vm.expectRevert(PoVWSunset.selector);
        token.mintPoVWRewardsForRecipient(user, 0);
    }

    function testFullStakingBudgetAndNextEpochRemainIdentical() public {
        vm.startPrank(owner);
        token.grantRole(token.STAKING_MINTER_ROLE(), minter);
        original.grantRole(original.STAKING_MINTER_ROLE(), minter);
        vm.stopPrank();
        upgrade();
        uint256[7] memory timestamps =
            [T - 1, T, T + 1, START + 211 * 2 days, START + 364 * 2 days, START + 1456 * 2 days, START + 1820 * 2 days];
        for (uint256 i; i < timestamps.length; ++i) {
            vm.warp(timestamps[i]);
            uint256 budget = original.getTotalStakingEmissionsAtEpochStart(original.getCurrentEpoch());
            uint256 remaining = budget - original.stakingClaimed();
            vm.startPrank(minter);
            original.mintStakingRewardsForRecipient(user, remaining);
            token.mintStakingRewardsForRecipient(user, remaining);
            vm.expectRevert(IZKC.TotalAllocationExceeded.selector);
            original.mintStakingRewardsForRecipient(user, 1);
            vm.expectRevert(IZKC.TotalAllocationExceeded.selector);
            token.mintStakingRewardsForRecipient(user, 1);
            vm.stopPrank();
            assertEq(token.stakingClaimed(), budget);
            assertEq(token.stakingClaimed(), original.stakingClaimed());
            assertEq(token.balanceOf(user), original.balanceOf(user));
            assertEq(token.claimedTotalSupply(), original.claimedTotalSupply());
            assertLe(token.claimedTotalSupply(), token.totalSupply());
        }
    }

    function testEveryEpochThroughTenYearsMatchesOriginalStakingAndFrozenPoVW() public {
        upgrade();
        uint256 frozenPoVW = original.getTotalPoVWEmissionsAtEpochStart(CUTOFF_EPOCH);
        uint256 stakingPaid;
        for (uint256 epoch; epoch <= 1820; ++epoch) {
            uint256 stakingEmission = original.getStakingEmissionsForEpoch(epoch);
            assertEq(token.getStakingEmissionsForEpoch(epoch), stakingEmission);
            assertEq(
                token.getTotalStakingEmissionsAtEpochStart(epoch), original.getTotalStakingEmissionsAtEpochStart(epoch)
            );
            if (epoch < CUTOFF_EPOCH) {
                assertEq(token.getSupplyAtEpochStart(epoch), original.getSupplyAtEpochStart(epoch));
                assertEq(token.getEmissionsForEpoch(epoch), original.getEmissionsForEpoch(epoch));
            } else {
                assertEq(token.getTotalPoVWEmissionsAtEpochStart(epoch), frozenPoVW);
                assertEq(token.getPoVWEmissionsForEpoch(epoch), 0);
                assertEq(token.getEmissionsForEpoch(epoch), stakingEmission);
                assertEq(
                    token.getSupplyAtEpochStart(epoch),
                    original.INITIAL_SUPPLY() + frozenPoVW + original.getTotalStakingEmissionsAtEpochStart(epoch)
                );
            }
            // Per-epoch rounding can leave dust relative to the cumulative budget.
            stakingPaid += stakingEmission;
            uint256 cumulativeBudget = token.getTotalStakingEmissionsAtEpochStart(epoch + 1);
            assertLe(stakingPaid, cumulativeBudget);
            assertLe(cumulativeBudget - stakingPaid, epoch + 1);
        }
    }
}
