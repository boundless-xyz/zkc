// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/ZKC.sol";
import "../../src/interfaces/IZKC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ZKCInitializersTest is Test {
    ZKC public zkc;

    address public owner = makeAddr("owner");
    address public minter1 = makeAddr("minter1");
    address public minter2 = makeAddr("minter2");
    address public notOwner = makeAddr("notOwner");
    address public user = makeAddr("user");

    function setUp() public {
        // Deploy implementation
        ZKC implementation = new ZKC();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            ZKC.initialize.selector,
            minter1,
            minter2,
            implementation.INITIAL_SUPPLY() / 2,
            implementation.INITIAL_SUPPLY() / 2,
            owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        zkc = ZKC(address(proxy));

        // Deploy new implementation for V2
        ZKC implementationV2 = new ZKC();

        // Upgrade to V2 and call initializeV2
        vm.prank(owner);
        zkc.upgradeToAndCall(address(implementationV2), abi.encodeWithSelector(ZKC.initializeV2.selector));
    }

    function test_epoch0StartTime_InitializedToMax() public view {
        // Verify epoch0StartTime is initialized to max value
        assertEq(zkc.epoch0StartTime(), type(uint256).max, "epoch0StartTime should be max uint256");
    }

    function test_getCurrentEpoch_RevertsBeforeInitializeV3() public {
        // getCurrentEpoch should revert with EpochsNotStarted when epoch0StartTime is max
        vm.expectRevert(abi.encodeWithSelector(IZKC.EpochsNotStarted.selector));
        zkc.getCurrentEpoch();
    }

    function test_getEpochStartTime_RevertsBeforeInitializeV3() public {
        // getEpochStartTime should revert with EpochsNotStarted when epoch0StartTime is max
        vm.expectRevert(abi.encodeWithSelector(IZKC.EpochsNotStarted.selector));
        zkc.getEpochStartTime(0);
    }

    function test_getEpochEndTime_RevertsBeforeInitializeV3() public {
        // getEpochEndTime should revert with EpochsNotStarted when getEpochStartTime reverts
        vm.expectRevert(abi.encodeWithSelector(IZKC.EpochsNotStarted.selector));
        zkc.getEpochEndTime(0);
    }

    function test_totalSupply_ReturnsInitialSupplyBeforeInitializeV3() public view {
        // totalSupply should return INITIAL_SUPPLY before epochs start
        assertEq(
            zkc.totalSupply(), zkc.INITIAL_SUPPLY(), "totalSupply should return INITIAL_SUPPLY before epochs start"
        );
    }

    function test_initializeV3_OnlyOwner() public {
        // Non-owner should not be able to call initializeV3
        bytes32 adminRole = zkc.ADMIN_ROLE();
        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notOwner, adminRole)
        );
        zkc.initializeV3();
    }

    function test_initializeV3_OwnerCanCall() public {
        // Owner should be able to call initializeV3
        uint256 blockTimestamp = block.timestamp;
        vm.prank(owner);
        zkc.initializeV3();

        // Verify epoch0StartTime was set to current block timestamp
        assertEq(zkc.epoch0StartTime(), blockTimestamp, "epoch0StartTime should be set to block.timestamp");
    }

    function test_initializeV3_FixesGetCurrentEpoch() public {
        // After initializeV3, getCurrentEpoch should work
        vm.prank(owner);
        zkc.initializeV3();

        // Should return epoch 0 immediately after initialization
        assertEq(zkc.getCurrentEpoch(), 0, "Should be in epoch 0");

        // Move forward 2 days (1 epoch)
        vm.warp(block.timestamp + zkc.EPOCH_DURATION());
        assertEq(zkc.getCurrentEpoch(), 1, "Should be in epoch 1");
    }

    function test_initializeV3_FixesGetEpochStartTime() public {
        uint256 initTime = block.timestamp;
        vm.prank(owner);
        zkc.initializeV3();

        // Should return correct start times for epochs
        assertEq(zkc.getEpochStartTime(0), initTime, "Epoch 0 start time");
        assertEq(zkc.getEpochStartTime(1), initTime + zkc.EPOCH_DURATION(), "Epoch 1 start time");
        assertEq(zkc.getEpochStartTime(10), initTime + (10 * zkc.EPOCH_DURATION()), "Epoch 10 start time");
    }

    function test_initializeV3_FixesGetEpochEndTime() public {
        uint256 initTime = block.timestamp;
        vm.prank(owner);
        zkc.initializeV3();

        // Should return correct end times for epochs
        assertEq(zkc.getEpochEndTime(0), initTime + zkc.EPOCH_DURATION() - 1, "Epoch 0 end time");
        assertEq(zkc.getEpochEndTime(1), initTime + (2 * zkc.EPOCH_DURATION()) - 1, "Epoch 1 end time");
    }

    function test_initializeV3_FixesTotalSupply() public {
        vm.prank(owner);
        zkc.initializeV3();

        // totalSupply should now work and return initial supply
        assertEq(zkc.totalSupply(), zkc.INITIAL_SUPPLY(), "Total supply should be initial supply at epoch 0");

        // Move forward to epoch 1
        vm.warp(block.timestamp + zkc.EPOCH_DURATION());
        assertTrue(zkc.totalSupply() > zkc.INITIAL_SUPPLY(), "Total supply should increase after epoch 0");
    }

    function test_initializeV3_CanOnlyCallOnce() public {
        // First call should succeed
        vm.prank(owner);
        zkc.initializeV3();

        // Second call should fail (already initialized to version 3)
        vm.prank(owner);
        vm.expectRevert();
        zkc.initializeV3();
    }

    function test_mintingRevertsBeforeInitializeV3() public {
        // Minting should revert when epoch0StartTime is max (after initializeV2 but before initializeV3)

        // Grant minting roles
        vm.startPrank(owner);
        zkc.grantRole(zkc.POVW_MINTER_ROLE(), user);
        zkc.grantRole(zkc.STAKING_MINTER_ROLE(), user);
        vm.stopPrank();

        // PoVW minting should revert with EpochsNotStarted (calls getCurrentEpoch)
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IZKC.EpochsNotStarted.selector));
        zkc.mintPoVWRewardsForRecipient(user, 100e18);

        // Staking minting should revert with EpochsNotStarted (calls getCurrentEpoch)
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IZKC.EpochsNotStarted.selector));
        zkc.mintStakingRewardsForRecipient(user, 100e18);
    }

    function test_emissionFunctionsWorkAfterInitializeV3() public {
        // Initialize V3 to start the epochs
        vm.prank(owner);
        zkc.initializeV3();

        // Now emission functions should work
        uint256 emissions = zkc.getEmissionsForEpoch(0);
        assertTrue(emissions > 0, "Emissions for epoch 0 should be greater than 0");

        uint256 povwEmissions = zkc.getPoVWEmissionsForEpoch(0);
        assertTrue(povwEmissions > 0, "PoVW emissions for epoch 0 should be greater than 0");
        assertEq(
            povwEmissions,
            (emissions * zkc.POVW_ALLOCATION_BPS()) / zkc.BASIS_POINTS(),
            "PoVW emissions should be 75% of total"
        );

        uint256 stakingEmissions = zkc.getStakingEmissionsForEpoch(0);
        assertTrue(stakingEmissions > 0, "Staking emissions for epoch 0 should be greater than 0");
        assertEq(
            stakingEmissions,
            (emissions * zkc.STAKING_ALLOCATION_BPS()) / zkc.BASIS_POINTS(),
            "Staking emissions should be 25% of total"
        );

        // Total allocations should equal total emissions
        assertEq(povwEmissions + stakingEmissions, emissions, "Sum of allocations should equal total emissions");
    }
}
