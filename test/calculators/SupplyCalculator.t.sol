// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {SupplyCalculator} from "../../src/calculators/SupplyCalculator.sol";
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

    uint256 public constant INITIAL_UNLOCKED = 500_000_000e18; // 500M tokens initially unlocked

    function setUp() public {
        // Deploy ZKC
        deployZKC();

        // Deploy SupplyCalculator
        deploySupplyCalculator();
    }

    function deployZKC() internal {
        // Deploy implementation
        ZKC implementation = new ZKC();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            ZKC.initialize.selector, minter1, minter2, implementation.INITIAL_SUPPLY(), 0, owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        zkc = ZKC(address(proxy));

        // Initialize V2 and V3
        vm.prank(owner);
        zkc.initializeV2();

        vm.prank(owner);
        zkc.initializeV3();

        // Perform initial mint
        address[] memory recipients = new address[](1);
        recipients[0] = user;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = zkc.INITIAL_SUPPLY();
        vm.prank(minter1);
        zkc.initialMint(recipients, amounts);

        // Grant minter roles
        vm.startPrank(owner);
        zkc.grantRole(zkc.POVW_MINTER_ROLE(), povwMinter);
        zkc.grantRole(zkc.STAKING_MINTER_ROLE(), stakingMinter);
        vm.stopPrank();
    }

    function deploySupplyCalculator() internal {
        // Deploy implementation
        SupplyCalculator implementation = new SupplyCalculator();

        // Deploy proxy and initialize
        bytes memory initData =
            abi.encodeWithSelector(SupplyCalculator.initialize.selector, address(zkc), INITIAL_UNLOCKED, owner);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        supplyCalculator = SupplyCalculator(address(proxy));
    }

    function testInitialization() public view {
        assertEq(address(supplyCalculator.zkc()), address(zkc));
        assertEq(supplyCalculator.unlocked(), INITIAL_UNLOCKED);
        assertTrue(supplyCalculator.hasRole(supplyCalculator.ADMIN_ROLE(), owner));
    }

    function testCirculatingSupplyAfterInitialMint() public {
        // Circulating supply should be just unlocked since total minted (1B)
        uint256 circulatingSupply = supplyCalculator.circulatingSupply();
        assertEq(circulatingSupply, INITIAL_UNLOCKED);
    }

    function testCirculatingSupplyAfterRewardsMinted() public {
        // Skip forward in time to simulate epochs passing
        vm.warp(block.timestamp + 4 weeks);

        // Mint some PoVW rewards
        uint256 povwRewards = 1_000_000e18; // 1M tokens
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, povwRewards);

        // Mint some staking rewards
        uint256 stakingRewards = 500_000e18; // 500K tokens
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, stakingRewards);

        uint256 expectedCirculating = INITIAL_UNLOCKED + povwRewards + stakingRewards;
        uint256 circulatingSupply = supplyCalculator.circulatingSupply();
        assertEq(circulatingSupply, expectedCirculating);
    }

    function testUpdateUnlockedValue() public {
        uint256 newUnlocked = 750_000_000e18; // 750M tokens

        vm.expectEmit(true, true, true, true);
        emit SupplyCalculator.UnlockedValueUpdated(INITIAL_UNLOCKED, newUnlocked);
        vm.prank(owner);
        supplyCalculator.updateUnlockedValue(newUnlocked);

        assertEq(supplyCalculator.unlocked(), newUnlocked);

        // Check circulating supply updated correctly
        uint256 circulatingSupply = supplyCalculator.circulatingSupply();
        assertEq(circulatingSupply, newUnlocked);
    }

    function testUpdateUnlockedValueAccessControl() public {
        uint256 newUnlocked = 750_000_000e18;

        // Non-admin should not be able to update
        vm.prank(user);
        vm.expectRevert();
        supplyCalculator.updateUnlockedValue(newUnlocked);

        // Admin should be able to update
        vm.prank(owner);
        supplyCalculator.updateUnlockedValue(newUnlocked);
        assertEq(supplyCalculator.unlocked(), newUnlocked);
    }

    function testUpgradeAccessControl() public {
        // Deploy new implementation
        SupplyCalculator newImplementation = new SupplyCalculator();

        // Non-admin should not be able to upgrade
        vm.prank(user);
        vm.expectRevert();
        supplyCalculator.upgradeToAndCall(address(newImplementation), "");

        // Admin should be able to upgrade
        vm.prank(owner);
        supplyCalculator.upgradeToAndCall(address(newImplementation), "");
    }

    function testCirculatingSupplyWithBurnedTokens() public {
        // Skip forward in time to simulate epochs passing
        vm.warp(block.timestamp + 4 weeks);

        // Mint some rewards
        uint256 rewards = 1_000_000e18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, rewards);

        // Burn some tokens
        uint256 burnAmount = 500_000e18;
        vm.prank(user);
        zkc.burn(burnAmount);

        uint256 expectedCirculating = INITIAL_UNLOCKED + rewards - burnAmount;
        uint256 circulatingSupply = supplyCalculator.circulatingSupply();
        assertEq(circulatingSupply, expectedCirculating);
    }

    function testCirculatingSupplyRounded() public {
        // Test with value that rounds down
        uint256 valueRoundDown = 500_000_000e18 + 0.3e18;
        vm.prank(owner);
        supplyCalculator.updateUnlockedValue(valueRoundDown);

        uint256 rounded18dp = supplyCalculator.circulatingSupplyRounded();
        assertEq(rounded18dp, 500_000_000e18);

        uint256 roundedAmount = supplyCalculator.circulatingSupplyAmountRounded();
        assertEq(roundedAmount, 500_000_000);

        // Test with value that rounds up
        uint256 valueRoundUp = 500_000_000e18 + 0.7e18;
        vm.prank(owner);
        supplyCalculator.updateUnlockedValue(valueRoundUp);

        rounded18dp = supplyCalculator.circulatingSupplyRounded();
        assertEq(rounded18dp, 500_000_001e18);

        roundedAmount = supplyCalculator.circulatingSupplyAmountRounded();
        assertEq(roundedAmount, 500_000_001);
    }

    function testTotalSupplyRounded() public {
        // Skip forward to start epochs
        uint256 epoch17TotalSupply = zkc.getSupplyAtEpochStart(17);
        uint256 epoch17ExpectedTotalSupply = 1006339775710604115000000000;
        assertEq(epoch17TotalSupply, epoch17ExpectedTotalSupply);

        vm.warp(block.timestamp + 17 * zkc.EPOCH_DURATION());

        // Get the theoretical total supply
        uint256 totalSupply = zkc.totalSupply();
        console.logUint(totalSupply);
        console.logUint(epoch17TotalSupply);
        assertEq(totalSupply, epoch17TotalSupply);

        // Get rounded values
        uint256 rounded18dp = supplyCalculator.totalSupplyRounded();
        uint256 roundedAmount = supplyCalculator.totalSupplyAmountRounded();

        // Verify rounding is correct
        assertEq(rounded18dp, 1006339776000000000000000000);
        assertEq(roundedAmount, 1006339776);
    }

    function testTotalClaimedSupplyRounded() public {
        // Skip forward in time to simulate epochs passing
        vm.warp(block.timestamp + 4 weeks);

        // Mint some rewards to create a claimed supply > initial supply
        uint256 rewards = 1_234_567.89e18;
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, rewards);

        // Get the claimed total supply
        uint256 claimedSupply = zkc.claimedTotalSupply();
        assertEq(claimedSupply, zkc.INITIAL_SUPPLY() + rewards);

        // Get rounded values
        uint256 rounded18dp = supplyCalculator.claimedTotalSupplyRounded();
        uint256 roundedAmount = supplyCalculator.claimedTotalSupplyAmountRounded();

        assertEq(rounded18dp, 1001234568000000000000000000);
        assertEq(roundedAmount, 1001234568);
    }
}
