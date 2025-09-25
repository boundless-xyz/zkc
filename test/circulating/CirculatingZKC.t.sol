// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/circulating/CirculatingZKC.sol";
import "../../src/ZKC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CirculatingZKCTest is Test {
    CirculatingZKC public circulatingZKC;
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

        // Deploy CirculatingZKC
        deployCirculatingZKC();
    }

    function deployZKC() internal {
        // Deploy implementation
        ZKC implementation = new ZKC();

        // Deploy proxy and initialize
        bytes memory initData =
            abi.encodeWithSelector(ZKC.initialize.selector, minter1, minter2, implementation.INITIAL_SUPPLY(), 0, owner);

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

    function deployCirculatingZKC() internal {
        // Deploy implementation
        CirculatingZKC implementation = new CirculatingZKC();

        // Deploy proxy and initialize
        bytes memory initData =
            abi.encodeWithSelector(CirculatingZKC.initialize.selector, address(zkc), INITIAL_UNLOCKED, owner);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        circulatingZKC = CirculatingZKC(address(proxy));
    }

    function testInitialization() public view {
        assertEq(address(circulatingZKC.zkc()), address(zkc));
        assertEq(circulatingZKC.unlocked(), INITIAL_UNLOCKED);
        assertTrue(circulatingZKC.hasRole(circulatingZKC.ADMIN_ROLE(), owner));
    }

    function testCirculatingSupplyAfterInitialMint() public {
        // Circulating supply should be just unlocked since total minted (1B)
        uint256 circulatingSupply = circulatingZKC.circulatingSupply();
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
        uint256 circulatingSupply = circulatingZKC.circulatingSupply();
        assertEq(circulatingSupply, expectedCirculating);
    }

    function testUpdateUnlockedValue() public {
        uint256 newUnlocked = 750_000_000e18; // 750M tokens

        vm.expectEmit(true, true, true, true);
        emit CirculatingZKC.UnlockedValueUpdated(INITIAL_UNLOCKED, newUnlocked);
        vm.prank(owner);
        circulatingZKC.updateUnlockedValue(newUnlocked);

        assertEq(circulatingZKC.unlocked(), newUnlocked);

        // Check circulating supply updated correctly
        uint256 circulatingSupply = circulatingZKC.circulatingSupply();
        assertEq(circulatingSupply, newUnlocked);
    }

    function testUpdateUnlockedValueAccessControl() public {
        uint256 newUnlocked = 750_000_000e18;

        // Non-admin should not be able to update
        vm.prank(user);
        vm.expectRevert();
        circulatingZKC.updateUnlockedValue(newUnlocked);

        // Admin should be able to update
        vm.prank(owner);
        circulatingZKC.updateUnlockedValue(newUnlocked);
        assertEq(circulatingZKC.unlocked(), newUnlocked);
    }

    function testUpgradeAccessControl() public {
        // Deploy new implementation
        CirculatingZKC newImplementation = new CirculatingZKC();

        // Non-admin should not be able to upgrade
        vm.prank(user);
        vm.expectRevert();
        circulatingZKC.upgradeToAndCall(address(newImplementation), "");

        // Admin should be able to upgrade
        vm.prank(owner);
        circulatingZKC.upgradeToAndCall(address(newImplementation), "");
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
        uint256 circulatingSupply = circulatingZKC.circulatingSupply();
        assertEq(circulatingSupply, expectedCirculating);
    }
}
