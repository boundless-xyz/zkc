// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {ZKC, PoVWSunset} from "../src/ZKC.sol";
import {ZKCOriginal} from "./reference/ZKCOriginal.sol";
import {veZKC} from "../src/veZKC.sol";
import {StakingRewards} from "../src/rewards/StakingRewards.sol";
import {SupplyCalculator} from "../src/calculators/SupplyCalculator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PoVWSunsetTest is Test {
    uint256 constant T = 1793836800;
    uint256 constant START = 1757536895;
    uint256 constant CUTOFF_EPOCH = 210;
    address constant ADMIN = address(0xa11ce);
    address USER;
    uint256 constant USER_KEY = 0xbeef;
    address constant MINTER = address(0x1001);
    ZKC token;
    ZKC original;
    veZKC stake;
    veZKC originalStake;
    StakingRewards rewards;
    StakingRewards originalRewards;

    function setUp() public {
        USER = vm.addr(USER_KEY);
        vm.warp(START);
        (token, stake, rewards) = deploySystem();
        (original, originalStake, originalRewards) = deploySystem();
        vm.warp(START + 1);
        vm.startPrank(USER);
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
                    abi.encodeCall(ZKCOriginal.initialize, (MINTER, address(0x1002), 1_000_000_000 ether, 0, ADMIN))
                )
            )
        );
        vm.startPrank(ADMIN);
        t.initializeV2();
        t.initializeV3();
        v = veZKC(
            address(new ERC1967Proxy(address(new veZKC()), abi.encodeCall(veZKC.initialize, (address(t), ADMIN))))
        );
        r = StakingRewards(
            address(
                new ERC1967Proxy(
                    address(new StakingRewards()),
                    abi.encodeCall(StakingRewards.initialize, (address(t), address(v), ADMIN))
                )
            )
        );
        t.grantRole(t.POVW_MINTER_ROLE(), MINTER);
        t.grantRole(t.STAKING_MINTER_ROLE(), address(r));
        vm.stopPrank();
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = USER;
        amounts[0] = 1_000_000_000 ether;
        vm.prank(MINTER);
        t.initialMint(recipients, amounts);
    }

    function upgrade() internal {
        ZKC implementation = new ZKC();
        vm.prank(ADMIN);
        token.upgradeToAndCall(address(implementation), "");
    }

    function testUpgradePreservesStateAndPreCutoffBehavior() public {
        vm.warp(T - 1);
        vm.prank(MINTER);
        token.mintPoVWRewardsForRecipient(USER, 10 ether);
        uint256 balance = token.balanceOf(USER);
        uint256 supply = token.claimedTotalSupply();
        uint256 allowance = token.allowance(USER, address(stake));
        uint256 theoretical = token.totalSupply();
        upgrade();
        assertEq(token.balanceOf(USER), balance);
        assertEq(token.claimedTotalSupply(), supply);
        assertEq(token.totalSupply(), theoretical);
        assertEq(token.allowance(USER, address(stake)), allowance);
        assertEq(token.nonces(USER), 0);
        assertEq(token.epoch0StartTime(), START);
        assertEq(token.poVWClaimed(), 10 ether);
        assertTrue(token.hasRole(token.POVW_MINTER_ROLE(), MINTER));
        assertTrue(token.hasRole(token.STAKING_MINTER_ROLE(), address(rewards)));
        vm.prank(MINTER);
        token.mintPoVWRewardsForRecipient(USER, 1 ether);
        assertEq(token.poVWClaimed(), 11 ether);
    }

    function testPoVWMintsRevertAtAndAfterCutoffEvenForOldBudgetOrZeroAmount() public {
        upgrade();
        vm.warp(T - 1);
        vm.prank(MINTER);
        token.mintPoVWRewardsForRecipient(USER, 1 ether);
        uint256 claimed = token.poVWClaimed();
        for (uint256 i; i < 2; ++i) {
            vm.warp(T + i);
            vm.startPrank(MINTER);
            vm.expectRevert(PoVWSunset.selector);
            token.mintPoVWRewardsForRecipient(USER, 1 ether);
            vm.expectRevert(PoVWSunset.selector);
            token.mintPoVWRewardsForRecipient(USER, 0);
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
        vm.prank(USER);
        uint256 expected = originalRewards.claimRewards(epochs);
        vm.prank(USER);
        uint256 actual = rewards.claimRewards(epochs);
        assertGt(actual, 0);
        assertEq(actual, expected);
        assertEq(token.stakingClaimed(), original.stakingClaimed());
        assertEq(token.balanceOf(USER), original.balanceOf(USER));
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
        vm.startPrank(USER);
        stake.initiateUnstake();
        originalStake.initiateUnstake();
        vm.stopPrank();
    }

    function completeBoth() internal {
        uint256 beforeBalance = token.balanceOf(USER);
        vm.startPrank(USER);
        stake.completeUnstake();
        originalStake.completeUnstake();
        vm.stopPrank();
        assertEq(token.balanceOf(USER) - beforeBalance, 1_000_000 ether);
        assertEq(token.balanceOf(USER), original.balanceOf(USER));
    }

    function testSupplyCalculatorAndPostCutoffGrowth() public {
        upgrade();
        SupplyCalculator c = SupplyCalculator(
            address(
                new ERC1967Proxy(
                    address(new SupplyCalculator()),
                    abi.encodeCall(SupplyCalculator.initialize, (address(token), 0, ADMIN))
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
        vm.prank(USER);
        vm.expectRevert();
        token.upgradeToAndCall(address(implementation), "");
        upgrade();
        vm.prank(ADMIN);
        vm.expectRevert();
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
                USER,
                address(0xcafe),
                100 ether,
                t.nonces(USER),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", t.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 sigS) = vm.sign(USER_KEY, digest);
        t.permit(USER, address(0xcafe), 100 ether, deadline, v, r, sigS);
    }

    function testNonzeroPermitNonceTransfersAndBurnsSurviveUpgrade() public {
        permitToken(token);
        permitToken(original);
        upgrade();
        vm.warp(T);
        assertEq(token.nonces(USER), 1);
        assertEq(token.allowance(USER, address(0xcafe)), 100 ether);
        vm.startPrank(address(0xcafe));
        token.transferFrom(USER, address(0x1234), 10 ether);
        original.transferFrom(USER, address(0x1234), 10 ether);
        vm.stopPrank();
        vm.startPrank(USER);
        token.transfer(address(0x1234), 5 ether);
        original.transfer(address(0x1234), 5 ether);
        token.burn(20 ether);
        original.burn(20 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(USER), original.balanceOf(USER));
        assertEq(token.balanceOf(address(0x1234)), original.balanceOf(address(0x1234)));
        assertEq(token.claimedTotalSupply(), original.claimedTotalSupply());
    }

    function testDelegationAndThirtyDayWithdrawalBoundaryUnchanged() public {
        vm.prank(USER);
        stake.delegateRewards(address(0xcafe));
        upgrade();
        vm.warp(T);
        vm.startPrank(USER);
        vm.expectRevert();
        stake.initiateUnstake();
        stake.delegateRewards(USER);
        stake.initiateUnstake();
        vm.warp(T + 30 days - 1);
        vm.expectRevert();
        stake.completeUnstake();
        vm.warp(T + 30 days);
        uint256 beforeBalance = token.balanceOf(USER);
        stake.completeUnstake();
        vm.stopPrank();
        assertEq(token.balanceOf(USER) - beforeBalance, 1_000_000 ether);
    }

    function testPriorClaimsStayClaimedAfterUpgrade() public {
        vm.warp(START + 5 days);
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 1;
        vm.prank(USER);
        uint256 expected = originalRewards.claimRewards(epochs);
        vm.prank(USER);
        assertEq(rewards.claimRewards(epochs), expected);
        uint256 claimed = token.stakingClaimed();
        upgrade();
        vm.warp(T + 3 days);
        assertEq(token.stakingClaimed(), claimed);
        vm.prank(USER);
        vm.expectRevert();
        rewards.claimRewards(epochs);
        epochs[0] = 210;
        vm.prank(USER);
        expected = originalRewards.claimRewards(epochs);
        vm.prank(USER);
        assertEq(rewards.claimRewards(epochs), expected);
    }

    function testUnstartedEpochsRetainOriginalSupplyReporting() public {
        token = ZKC(
            address(
                new ERC1967Proxy(
                    address(new ZKC()),
                    abi.encodeCall(ZKC.initialize, (MINTER, address(0x1002), 1_000_000_000 ether, 0, ADMIN))
                )
            )
        );
        assertEq(token.epoch0StartTime(), 0);
        assertEq(token.getSupplyAtEpochStart(300), original.getSupplyAtEpochStart(300));
        vm.prank(ADMIN);
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
        vm.startPrank(MINTER);
        token.mintPoVWRewardsForRecipient(USER, budget);
        vm.expectRevert();
        token.mintPoVWRewardsForRecipient(USER, 1);
        vm.warp(T);
        vm.expectRevert(PoVWSunset.selector);
        token.mintPoVWRewardsForRecipient(USER, 0);
        vm.stopPrank();
        assertEq(token.poVWClaimed(), budget);
    }
}
