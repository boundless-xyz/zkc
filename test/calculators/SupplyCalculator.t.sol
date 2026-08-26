// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {SupplyCalculator} from "../../src/calculators/SupplyCalculator.sol";
import {Supply} from "../../src/libraries/Supply.sol";
import "../../src/ZKC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SupplyCalculatorTest is Test {
    SupplyCalculator public supplyCalculator;
    ZKC public zkc;

    address public owner = makeAddr("owner");
    address public minter1 = makeAddr("minter1");
    address public minter2 = makeAddr("minter2");
    address public povwMinter = makeAddr("povwMinter");
    address public stakingMinter = makeAddr("stakingMinter");
    address public user = makeAddr("user");

    uint256 internal constant WARP_TIME = 1787677200; // 2026-08-25 17:00 UTC
    uint256 internal constant ONE_WEEK = 7 days;
    uint256 internal constant PRE_CLIFF_EPOCHS = 10;
    uint256 internal constant UNLOCKED_6M = 253_286_190e18;
    uint256 internal constant CLIFF_12M = 1789430400; // 2026-09-15
    uint256 internal constant CLIFF_13M = 1792022400; // 2026-10-15
    uint256 internal constant CLIFF_24M = 1820966400; // 2027-09-15
    uint256 internal constant CLIFF_26M = 1826236800; // 2027-11-15
    uint256 internal constant CLIFF_36M = 1852588800; // 2028-09-15
    uint256 internal constant TGE = 1757894400; // 2025-09-15

    function setUp() public {
        vm.warp(WARP_TIME);
        deployZKC();
        deploySupplyCalculator();
    }

    function deployZKC() internal {
        ZKC implementation = new ZKC();

        bytes memory initData = abi.encodeWithSelector(
            ZKC.initialize.selector, minter1, minter2, implementation.INITIAL_SUPPLY(), 0, owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        zkc = ZKC(address(proxy));

        vm.prank(owner);
        zkc.initializeV2();

        vm.prank(owner);
        zkc.initializeV3();

        address[] memory recipients = new address[](1);
        recipients[0] = user;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = zkc.INITIAL_SUPPLY();
        vm.prank(minter1);
        zkc.initialMint(recipients, amounts);

        vm.startPrank(owner);
        zkc.grantRole(zkc.POVW_MINTER_ROLE(), povwMinter);
        zkc.grantRole(zkc.STAKING_MINTER_ROLE(), stakingMinter);
        vm.stopPrank();
    }

    function deploySupplyCalculator() internal {
        SupplyCalculator implementation = new SupplyCalculator();

        bytes memory initData =
            abi.encodeWithSelector(SupplyCalculator.initialize.selector, address(zkc), UNLOCKED_6M, owner);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        supplyCalculator = SupplyCalculator(address(proxy));
    }

    function testInitialization() public view {
        assertEq(address(supplyCalculator.zkc()), address(zkc));
        assertTrue(supplyCalculator.hasRole(supplyCalculator.ADMIN_ROLE(), owner));
    }

    function testCurrentUnlockedLockedCirculating() public view {
        assertEq(supplyCalculator.unlocked(), UNLOCKED_6M);
        assertEq(supplyCalculator.locked(), Supply.INITIAL_SUPPLY - UNLOCKED_6M);
        assertEq(supplyCalculator.circulatingSupply(), UNLOCKED_6M);
    }

    function testScheduleCliffs() public view {
        assertEq(supplyCalculator.unlockedAtTimestamp(CLIFF_12M - 1), UNLOCKED_6M);
        assertEq(supplyCalculator.unlockedAtTimestamp(CLIFF_12M), 471_464_643e18);
        assertEq(supplyCalculator.unlockedAtTimestamp(CLIFF_13M), 490_861_950e18);
        assertEq(supplyCalculator.unlockedAtTimestamp(CLIFF_24M), 767_232_327e18);
        assertEq(supplyCalculator.unlockedAtTimestamp(CLIFF_26M), 806_026_940e18);
        assertEq(supplyCalculator.unlockedAtTimestamp(CLIFF_36M), Supply.INITIAL_SUPPLY);
        assertEq(supplyCalculator.unlockedAtTimestamp(CLIFF_36M + 1 days), Supply.INITIAL_SUPPLY);
    }

    function testBeforeTge() public view {
        assertEq(supplyCalculator.unlockedAtTimestamp(TGE - 1), 0);
        assertEq(supplyCalculator.lockedAtTimestamp(TGE - 1), Supply.INITIAL_SUPPLY);
    }

    function testAtTimestampMatchesBlockTimestampGetters() public {
        uint256[4] memory timestamps = [uint256(WARP_TIME), CLIFF_12M, CLIFF_24M, CLIFF_36M];

        for (uint256 i = 0; i < timestamps.length; ++i) {
            vm.warp(timestamps[i]);
            assertEq(supplyCalculator.unlocked(), supplyCalculator.unlockedAtTimestamp(timestamps[i]));
            assertEq(supplyCalculator.locked(), supplyCalculator.lockedAtTimestamp(timestamps[i]));
        }
    }

    function testLockedPlusUnlockedEqualsInitialSupply() public view {
        uint256[5] memory timestamps = [uint256(TGE - 1), WARP_TIME, CLIFF_12M, CLIFF_24M, CLIFF_36M];

        for (uint256 i = 0; i < timestamps.length; ++i) {
            assertEq(
                supplyCalculator.unlockedAtTimestamp(timestamps[i]) + supplyCalculator.lockedAtTimestamp(timestamps[i]),
                Supply.INITIAL_SUPPLY
            );
        }
    }

    function testCirculatingSupplyAfterInitialMint() public view {
        uint256 expectedCirculating = zkc.claimedTotalSupply() - supplyCalculator.locked();
        assertEq(supplyCalculator.circulatingSupply(), expectedCirculating);
        assertEq(supplyCalculator.circulatingSupply(), UNLOCKED_6M);
    }

    function _warpPreCliffWithEpochs() internal {
        vm.warp(WARP_TIME + PRE_CLIFF_EPOCHS * zkc.EPOCH_DURATION());
    }

    function testCirculatingSupplyAfterRewardsMinted() public {
        _warpPreCliffWithEpochs();

        uint256 povwRewards = 1_000_000e18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, povwRewards);

        uint256 stakingRewards = 500_000e18;
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, stakingRewards);

        uint256 expectedCirculating = zkc.claimedTotalSupply() - supplyCalculator.locked();
        assertEq(supplyCalculator.circulatingSupply(), expectedCirculating);
        assertEq(supplyCalculator.circulatingSupply(), UNLOCKED_6M + povwRewards + stakingRewards);
    }

    function testUpgradeAccessControl() public {
        SupplyCalculator newImplementation = new SupplyCalculator();

        vm.prank(user);
        vm.expectRevert();
        supplyCalculator.upgradeToAndCall(address(newImplementation), "");

        vm.prank(owner);
        supplyCalculator.upgradeToAndCall(address(newImplementation), "");
    }

    function testCirculatingSupplyWithBurnedTokens() public {
        _warpPreCliffWithEpochs();

        uint256 rewards = 1_000_000e18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, rewards);

        uint256 burnAmount = 500_000e18;
        vm.prank(user);
        zkc.burn(burnAmount);

        uint256 expectedCirculating = zkc.claimedTotalSupply() - supplyCalculator.locked();
        assertEq(supplyCalculator.circulatingSupply(), expectedCirculating);
        assertEq(supplyCalculator.circulatingSupply(), UNLOCKED_6M + rewards - burnAmount);
    }

    function testCirculatingSupplyRounded() public {
        vm.warp(WARP_TIME + ONE_WEEK);

        uint256 fractionalMint = 0.3e18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, fractionalMint);

        assertEq(supplyCalculator.circulatingSupplyRounded(), UNLOCKED_6M);
        assertEq(supplyCalculator.circulatingSupplyAmountRounded(), UNLOCKED_6M / 1e18);

        uint256 extraMint = 0.4e18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, extraMint);

        assertEq(supplyCalculator.circulatingSupplyRounded(), UNLOCKED_6M + 1e18);
        assertEq(supplyCalculator.circulatingSupplyAmountRounded(), UNLOCKED_6M / 1e18 + 1);
    }

    function testTotalSupplyAtTimestampBeforeEpochs() public {
        ZKC freshZkc = _deployZkcWithoutEpochs();
        SupplyCalculator calc = _deployCalculatorForZkc(freshZkc);

        assertEq(calc.totalSupplyAtTimestamp(WARP_TIME), Supply.INITIAL_SUPPLY);
        assertEq(calc.totalSupplyAtTimestamp(type(uint256).max), Supply.INITIAL_SUPPLY);
    }

    function testTotalSupplyAtTimestampAfterEpochs() public {
        uint256 epoch0Start = zkc.epoch0StartTime();
        uint256 epoch17Timestamp = epoch0Start + 17 * zkc.EPOCH_DURATION();
        uint256 epoch17Supply = zkc.getSupplyAtEpochStart(17);

        assertEq(supplyCalculator.totalSupplyAtTimestamp(epoch0Start - 1), Supply.INITIAL_SUPPLY);
        assertEq(supplyCalculator.totalSupplyAtTimestamp(epoch17Timestamp), epoch17Supply);
    }

    function testTotalSupplyRoundedAtTimestamp() public {
        uint256 epoch0Start = zkc.epoch0StartTime();
        uint256 epoch17Timestamp = epoch0Start + 17 * zkc.EPOCH_DURATION();
        uint256 epoch17Supply = zkc.getSupplyAtEpochStart(17);

        assertEq(supplyCalculator.totalSupplyRoundedAtTimestamp(epoch17Timestamp), 1006339776000000000000000000);
        assertEq(supplyCalculator.totalSupplyAmountRoundedAtTimestamp(epoch17Timestamp), 1006339776);
        assertEq(supplyCalculator.totalSupplyAtTimestamp(epoch17Timestamp), epoch17Supply);
    }

    function testTotalSupplyRounded() public {
        uint256 epoch0Start = zkc.epoch0StartTime();
        vm.warp(epoch0Start + 17 * zkc.EPOCH_DURATION());

        uint256 epoch17TotalSupply = zkc.getSupplyAtEpochStart(17);
        assertEq(zkc.totalSupply(), epoch17TotalSupply);

        assertEq(supplyCalculator.totalSupplyRounded(), 1006339776000000000000000000);
        assertEq(supplyCalculator.totalSupplyAmountRounded(), 1006339776);
    }

    function testTotalClaimedSupplyRounded() public {
        vm.warp(block.timestamp + 4 weeks);

        uint256 rewards = 1_234_567.89e18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, rewards);

        assertEq(zkc.claimedTotalSupply(), zkc.INITIAL_SUPPLY() + rewards);
        assertEq(supplyCalculator.claimedTotalSupplyRounded(), 1001234568000000000000000000);
        assertEq(supplyCalculator.claimedTotalSupplyAmountRounded(), 1001234568);
    }

    function _deployZkcWithoutEpochs() internal returns (ZKC) {
        ZKC implementation = new ZKC();
        bytes memory initData = abi.encodeWithSelector(
            ZKC.initialize.selector, minter1, minter2, implementation.INITIAL_SUPPLY(), 0, owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ZKC freshZkc = ZKC(address(proxy));
        vm.prank(owner);
        freshZkc.initializeV2();
        return freshZkc;
    }

    function _deployCalculatorForZkc(ZKC targetZkc) internal returns (SupplyCalculator) {
        SupplyCalculator implementation = new SupplyCalculator();
        bytes memory initData =
            abi.encodeWithSelector(SupplyCalculator.initialize.selector, address(targetZkc), UNLOCKED_6M, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return SupplyCalculator(address(proxy));
    }
}
