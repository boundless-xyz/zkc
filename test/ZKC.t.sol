// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZKC} from "../src/ZKC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ZKCTest is Test {
    ZKC public token;
    address public owner;
    address public initialMinter1;
    address public initialMinter2;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18; // 1B tokens
    uint256 public constant MINTER1_AMOUNT = (TOTAL_SUPPLY * 55) / 100; // 55% of 1B
    uint256 public constant MINTER2_AMOUNT = (TOTAL_SUPPLY * 45) / 100; // 45% of 1B

    bytes32 public ADMIN_ROLE;
    bytes32 public MINTER_ROLE;
    bytes32 public POVW_MINTER_ROLE;
    bytes32 public STAKING_MINTER_ROLE;

    function setUp() public {
        owner = makeAddr("owner");
        initialMinter1 = makeAddr("initialMinter1");
        initialMinter2 = makeAddr("initialMinter2");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");
        // Deploy implementation
        ZKC implementation = new ZKC();

        // Deploy proxy
        token = ZKC(address(new ERC1967Proxy(address(implementation), "")));

        ADMIN_ROLE = token.ADMIN_ROLE();
        MINTER_ROLE = token.MINTER_ROLE();
        POVW_MINTER_ROLE = token.POVW_MINTER_ROLE();
        STAKING_MINTER_ROLE = token.STAKING_MINTER_ROLE();

        // Initialize
        token.initialize(initialMinter1, initialMinter2, MINTER1_AMOUNT, MINTER2_AMOUNT, owner);
    }

    function test_Initialization() public view {
        assertEq(token.name(), "ZK Coin");
        assertEq(token.symbol(), "ZKC");
        assertEq(token.decimals(), 18);
        assertEq(token.initialMinter1(), initialMinter1);
        assertEq(token.initialMinter2(), initialMinter2);
        assertEq(token.initialMinter1Remaining(), MINTER1_AMOUNT);
        assertEq(token.initialMinter2Remaining(), MINTER2_AMOUNT);

        // Verify initial role assignments
        assertTrue(IAccessControl(address(token)).hasRole(ADMIN_ROLE, owner));

        assertFalse(IAccessControl(address(token)).hasRole(ADMIN_ROLE, initialMinter1));
        assertFalse(IAccessControl(address(token)).hasRole(ADMIN_ROLE, initialMinter2));
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, initialMinter1));
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, initialMinter2));
    }

    function test_InitialMinting() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        // Minter 1 mints their full allocation
        recipients[0] = user1;
        recipients[1] = user2;
        amounts[0] = MINTER1_AMOUNT / 2;
        amounts[1] = MINTER1_AMOUNT / 2;

        vm.prank(initialMinter1);
        token.initialMint(recipients, amounts);
        assertEq(token.balanceOf(user1), MINTER1_AMOUNT / 2);
        assertEq(token.balanceOf(user2), MINTER1_AMOUNT / 2);
        assertEq(token.initialMinter1Remaining(), 0);

        // Minter 2 mints their full allocation
        recipients[0] = user2;
        recipients[1] = user3;
        amounts[0] = MINTER2_AMOUNT / 2;
        amounts[1] = MINTER2_AMOUNT / 2;

        vm.prank(initialMinter2);
        token.initialMint(recipients, amounts);
        assertEq(token.balanceOf(user2), MINTER1_AMOUNT / 2 + MINTER2_AMOUNT / 2);
        assertEq(token.balanceOf(user3), MINTER2_AMOUNT / 2);
        assertEq(token.initialMinter2Remaining(), 0);

        assertEq(token.totalSupply(), TOTAL_SUPPLY);
    }

    function test_InitialMintersCannotOvermint() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        // Verify initialMinters have no special role
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, initialMinter1));
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, initialMinter2));
        assertFalse(IAccessControl(address(token)).hasRole(ADMIN_ROLE, initialMinter1));
        assertFalse(IAccessControl(address(token)).hasRole(ADMIN_ROLE, initialMinter2));

        // Try to mint more than allocation
        recipients[0] = user1;
        amounts[0] = MINTER1_AMOUNT + 1;

        vm.prank(initialMinter1);
        vm.expectRevert();
        token.initialMint(recipients, amounts);

        // Try to mint after allocation is used
        amounts[0] = MINTER1_AMOUNT;
        vm.prank(initialMinter1);
        token.initialMint(recipients, amounts);

        vm.prank(initialMinter1);
        vm.expectRevert();
        token.initialMint(recipients, amounts);

        // Test initialMinter2 overmint
        amounts[0] = MINTER2_AMOUNT + 1;
        vm.prank(initialMinter2);
        vm.expectRevert();
        token.initialMint(recipients, amounts);
    }

    function test_InitialMintersCanPartialMint() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        // Verify initialMinters have no special role
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, initialMinter1));
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, initialMinter2));
        assertFalse(IAccessControl(address(token)).hasRole(ADMIN_ROLE, initialMinter1));
        assertFalse(IAccessControl(address(token)).hasRole(ADMIN_ROLE, initialMinter2));

        // Minter 1 mints half their allocation
        recipients[0] = user1;
        amounts[0] = MINTER1_AMOUNT / 2;

        vm.prank(initialMinter1);
        token.initialMint(recipients, amounts);
        assertEq(token.balanceOf(user1), MINTER1_AMOUNT / 2);
        assertEq(token.initialMinter1Remaining(), MINTER1_AMOUNT / 2);

        // Minter 1 mints remaining half
        // check they can't overmint
        uint256[] memory overMintAmounts1 = new uint256[](1);
        overMintAmounts1[0] = MINTER1_AMOUNT / 2 + 1;
        vm.prank(initialMinter1);
        vm.expectRevert();
        token.initialMint(recipients, overMintAmounts1);

        // check they can mint the remaining
        amounts[0] = MINTER1_AMOUNT / 2;
        vm.prank(initialMinter1);
        token.initialMint(recipients, amounts);
        assertEq(token.balanceOf(user1), MINTER1_AMOUNT);
        assertEq(token.initialMinter1Remaining(), 0);

        // Test initialMinter2 partial minting
        recipients[0] = user2;
        amounts[0] = MINTER2_AMOUNT / 2;

        vm.prank(initialMinter2);
        token.initialMint(recipients, amounts);
        assertEq(token.balanceOf(user2), MINTER2_AMOUNT / 2);
        assertEq(token.initialMinter2Remaining(), MINTER2_AMOUNT / 2);

        // Check they can't overmint
        vm.prank(initialMinter2);
        vm.expectRevert();
        uint256[] memory overMintAmounts2 = new uint256[](1);
        overMintAmounts2[0] = MINTER2_AMOUNT / 2 + 1;
        token.initialMint(recipients, overMintAmounts2);

        // Check they can mint the remaining
        amounts[0] = MINTER2_AMOUNT / 2;
        vm.prank(initialMinter2);
        token.initialMint(recipients, amounts);
        assertEq(token.balanceOf(user2), MINTER2_AMOUNT);
        assertEq(token.initialMinter2Remaining(), 0);
    }

    function test_OnlyInitialMintersCanMint() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = user1;
        amounts[0] = 1000;

        // Verify initialMinters have no special role
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, initialMinter1));
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, initialMinter2));
        assertFalse(IAccessControl(address(token)).hasRole(ADMIN_ROLE, initialMinter1));
        assertFalse(IAccessControl(address(token)).hasRole(ADMIN_ROLE, initialMinter2));

        vm.prank(user1);
        vm.expectRevert();
        token.initialMint(recipients, amounts);
    }

    function test_RegularMinting() public {
        // Complete initial minting
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        recipients[0] = user1;
        amounts[0] = MINTER1_AMOUNT;
        vm.prank(initialMinter1);
        token.initialMint(recipients, amounts);

        recipients[0] = user2;
        amounts[0] = MINTER2_AMOUNT;
        vm.prank(initialMinter2);
        token.initialMint(recipients, amounts);

        // Verify owner has admin role
        assertTrue(IAccessControl(address(token)).hasRole(ADMIN_ROLE, owner));

        // Grant minter role and verify
        vm.prank(owner);
        IAccessControl(address(token)).grantRole(MINTER_ROLE, user3);
        assertTrue(IAccessControl(address(token)).hasRole(MINTER_ROLE, user3));

        // Verify minter can mint
        vm.prank(user3);
        token.mint(user4, 1000);
        assertEq(token.balanceOf(user4), 1000);

        // check total supply
        assertEq(token.totalSupply(), TOTAL_SUPPLY + 1000);

        // Verify non-minter cannot mint
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, user2));
        vm.prank(user2);
        vm.expectRevert();
        token.mint(user3, 1000);
    }

    function test_RoleGrantAndRevocation() public {
        // Grant minter role
        vm.prank(owner);
        IAccessControl(address(token)).grantRole(MINTER_ROLE, user1);
        assertTrue(IAccessControl(address(token)).hasRole(MINTER_ROLE, user1));

        // Revoke minter role
        vm.prank(owner);
        IAccessControl(address(token)).revokeRole(MINTER_ROLE, user1);
        assertFalse(IAccessControl(address(token)).hasRole(MINTER_ROLE, user1));

        // Verify minter can no longer mint
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user2, 1000);
    }

    function test_AdminRoleRenouncement() public {
        // Verify initial admin role
        assertTrue(IAccessControl(address(token)).hasRole(ADMIN_ROLE, owner));

        // Admin renounces role
        vm.prank(owner);
        IAccessControl(address(token)).renounceRole(ADMIN_ROLE, owner);

        // Verify admin role is gone
        assertFalse(IAccessControl(address(token)).hasRole(ADMIN_ROLE, owner));

        // Verify admin can no longer grant roles
        vm.prank(owner);
        vm.expectRevert();
        IAccessControl(address(token)).grantRole(MINTER_ROLE, user1);
    }

    // ============ INFLATION TESTS ============

    function test_InflationConstants() public view {
        assertEq(token.INITIAL_SUPPLY(), 1_000_000_000 * 10**18);
        assertEq(token.INITIAL_INFLATION_RATE(), 700); // 7.00%
        assertEq(token.FINAL_INFLATION_RATE(), 300);   // 3.00%
        assertEq(token.INFLATION_STEP(), 50);          // 0.50%
        assertEq(token.BASIS_POINTS(), 10000);
        assertEq(token.EPOCH_DURATION(), 2 days);
        assertEq(token.EPOCHS_PER_YEAR(), 182);
        assertEq(token.POVW_ALLOCATION(), 75);         // 75%
        assertEq(token.STAKING_ALLOCATION(), 25);      // 25%
    }

    function test_InflationRateCalculation() public view {
        // Year 1: 7.00%
        assertEq(token.getAnnualInflationRate(0), 700);
        assertEq(token.getAnnualInflationRate(91), 700);  // Mid-year 1
        assertEq(token.getAnnualInflationRate(181), 700); // End of year 1

        // Year 2: 6.50%
        assertEq(token.getAnnualInflationRate(182), 650);
        assertEq(token.getAnnualInflationRate(273), 650); // Mid-year 2
        assertEq(token.getAnnualInflationRate(363), 650); // End of year 2

        // Year 3: 6.00%
        assertEq(token.getAnnualInflationRate(364), 600);

        // Year 8: 3.50%
        assertEq(token.getAnnualInflationRate(1274), 350); // 7 * 182 = 1274

        // Year 9 and beyond: 3.00% (floor)
        assertEq(token.getAnnualInflationRate(1456), 300); // 8 * 182 = 1456
        assertEq(token.getAnnualInflationRate(1638), 300); // 9 * 182 = 1638
        assertEq(token.getAnnualInflationRate(10000), 300); // Far future
    }

    function test_TheoreticalSupplyCalculation() public view {
        // Epoch 0: Initial supply
        assertEq(token.getTheoreticalSupplyAtEpoch(0), token.INITIAL_SUPPLY());

        // Epoch 1: First inflation
        uint256 supply1 = token.getTheoreticalSupplyAtEpoch(1);
        assertTrue(supply1 > token.INITIAL_SUPPLY());

        // Supply should grow over time
        uint256 supply10 = token.getTheoreticalSupplyAtEpoch(10);
        uint256 supply100 = token.getTheoreticalSupplyAtEpoch(100);
        uint256 supply1000 = token.getTheoreticalSupplyAtEpoch(1000);

        assertTrue(supply10 > supply1);
        assertTrue(supply100 > supply10);
        assertTrue(supply1000 > supply100);

        // Verify compound growth (not linear)
        uint256 supply2 = token.getTheoreticalSupplyAtEpoch(2);
        uint256 epochInflation1 = supply1 - token.INITIAL_SUPPLY();
        uint256 epochInflation2 = supply2 - supply1;
        
        // Second epoch inflation should be slightly larger due to compound effect
        assertTrue(epochInflation2 > epochInflation1);
    }

    function test_EpochInflationAmount() public view {
        // Epoch 0 has no inflation
        assertEq(token.getEpochInflationAmount(0), 0);

        // Epoch 1 should have some inflation
        uint256 inflation1 = token.getEpochInflationAmount(1);
        assertTrue(inflation1 > 0);

        // Later epochs should have different amounts
        uint256 inflation10 = token.getEpochInflationAmount(10);
        uint256 inflation100 = token.getEpochInflationAmount(100);

        assertTrue(inflation10 > 0);
        assertTrue(inflation100 > 0);

        // Inflation should grow over time due to compound effect
        assertTrue(inflation10 > inflation1);
        assertTrue(inflation100 > inflation10);
    }

    function test_AllocationCalculations() public view {
        uint256 epoch = 10;
        uint256 totalInflation = token.getTotalEpochInflation(epoch);
        
        uint256 povwAllocation = token.getPoVWAllocationForEpoch(epoch);
        uint256 stakingAllocation = token.getStakingAllocationForEpoch(epoch);

        // Verify percentage splits (allow for rounding)
        assertEq(povwAllocation, (totalInflation * 75) / 100);
        assertEq(stakingAllocation, (totalInflation * 25) / 100);
        
        // Verify allocations add up to total (within 1 wei due to rounding)
        uint256 totalAllocated = povwAllocation + stakingAllocation;
        assertTrue(totalAllocated >= totalInflation - 1 && totalAllocated <= totalInflation + 1);
    }

    function test_MintPoVWReward() public {
        // Setup: Grant POVW_MINTER_ROLE to user1
        vm.prank(owner);
        IAccessControl(address(token)).grantRole(POVW_MINTER_ROLE, user1);

        // Warp time to simulate epoch progression  
        vm.warp(block.timestamp + 10 days); // 5 epochs
        
        // Get current epoch (deploymentTime gets initialized on first mint call)
        uint256 epoch = token.getCurrentEpoch();
        if (epoch == 0) epoch = 1; // Use epoch 1 if deploymentTime not set yet
        uint256 povwAllocation = token.getPoVWAllocationForEpoch(epoch);
        uint256 mintAmount = povwAllocation / 2; // Mint half of allocation

        uint256 balanceBefore = token.balanceOf(user2);
        
        vm.prank(user1);
        token.mintPoVWReward(user2, mintAmount, epoch);

        uint256 balanceAfter = token.balanceOf(user2);
        assertEq(balanceAfter - balanceBefore, mintAmount);

        // Verify tracking
        assertEq(token.epochPoVWMinted(epoch), mintAmount);
        assertEq(token.getPoVWRemainingForEpoch(epoch), povwAllocation - mintAmount);
    }

    function test_MintStakingReward() public {
        // Setup: Grant STAKING_MINTER_ROLE to user1
        vm.prank(owner);
        IAccessControl(address(token)).grantRole(STAKING_MINTER_ROLE, user1);

        // Warp time to simulate epoch progression
        vm.warp(block.timestamp + 10 days); // 5 epochs

        // Get current epoch (deploymentTime gets initialized on first mint call)
        uint256 epoch = token.getCurrentEpoch();
        if (epoch == 0) epoch = 1; // Use epoch 1 if deploymentTime not set yet
        uint256 stakingAllocation = token.getStakingAllocationForEpoch(epoch);
        uint256 mintAmount = stakingAllocation / 3; // Mint third of allocation

        uint256 balanceBefore = token.balanceOf(user3);
        
        vm.prank(user1);
        token.mintStakingReward(user3, mintAmount, epoch);

        uint256 balanceAfter = token.balanceOf(user3);
        assertEq(balanceAfter - balanceBefore, mintAmount);

        // Verify tracking
        assertEq(token.epochStakingMinted(epoch), mintAmount);
        assertEq(token.getStakingRemainingForEpoch(epoch), stakingAllocation - mintAmount);
    }

    function test_InflationAllocationEnforcement() public {
        // Setup roles
        vm.startPrank(owner);
        IAccessControl(address(token)).grantRole(POVW_MINTER_ROLE, user1);
        IAccessControl(address(token)).grantRole(STAKING_MINTER_ROLE, user2);
        vm.stopPrank();

        // Warp time
        vm.warp(block.timestamp + 4 days); // 2 epochs

        // Get current epoch (deploymentTime gets initialized on first mint call)
        uint256 epoch = token.getCurrentEpoch();
        if (epoch == 0) epoch = 1; // Use epoch 1 if deploymentTime not set yet
        uint256 povwAllocation = token.getPoVWAllocationForEpoch(epoch);
        uint256 stakingAllocation = token.getStakingAllocationForEpoch(epoch);

        // Try to mint more than PoVW allocation (should fail)
        vm.prank(user1);
        vm.expectRevert("Exceeds PoVW allocation for epoch");
        token.mintPoVWReward(user1, povwAllocation + 1, epoch);

        // Try to mint more than staking allocation (should fail)
        vm.prank(user2);
        vm.expectRevert("Exceeds staking allocation for epoch");
        token.mintStakingReward(user2, stakingAllocation + 1, epoch);

        // Mint full PoVW allocation
        vm.prank(user1);
        token.mintPoVWReward(user1, povwAllocation, epoch);

        // Try to mint more PoVW (should fail)
        vm.prank(user1);
        vm.expectRevert("Exceeds PoVW allocation for epoch");
        token.mintPoVWReward(user1, 1, epoch);

        // Mint full staking allocation
        vm.prank(user2);
        token.mintStakingReward(user2, stakingAllocation, epoch);

        // Try to mint more staking (should fail)
        vm.prank(user2);
        vm.expectRevert("Exceeds staking allocation for epoch");
        token.mintStakingReward(user2, 1, epoch);
    }

    function test_OnlyAuthorizedCanMintInflation() public {
        vm.warp(block.timestamp + 2 days); // 1 epoch
        
        // Get current epoch (deploymentTime gets initialized on first mint call)
        uint256 epoch = token.getCurrentEpoch();
        if (epoch == 0) epoch = 1; // Use epoch 1 if deploymentTime not set yet
        uint256 amount = 1000;

        // user1 without role cannot mint PoVW
        vm.prank(user1);
        vm.expectRevert();
        token.mintPoVWReward(user1, amount, epoch);

        // user2 without role cannot mint staking
        vm.prank(user2);
        vm.expectRevert();
        token.mintStakingReward(user2, amount, epoch);

        // Grant roles
        vm.startPrank(owner);
        IAccessControl(address(token)).grantRole(POVW_MINTER_ROLE, user1);
        IAccessControl(address(token)).grantRole(STAKING_MINTER_ROLE, user2);
        vm.stopPrank();

        // Now they can mint
        vm.prank(user1);
        token.mintPoVWReward(user1, amount, epoch);

        vm.prank(user2);
        token.mintStakingReward(user2, amount, epoch);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.balanceOf(user2), amount);
    }

    function test_InvalidEpochMinting() public {
        // Setup roles
        vm.startPrank(owner);
        IAccessControl(address(token)).grantRole(POVW_MINTER_ROLE, user1);
        IAccessControl(address(token)).grantRole(STAKING_MINTER_ROLE, user2);
        vm.stopPrank();

        // Try to mint for epoch 0 (should fail with "Invalid epoch")
        vm.prank(user1);
        vm.expectRevert("Invalid epoch");
        token.mintPoVWReward(user1, 1000, 0);

        // Initialize deployment time by minting for epoch 1 first
        vm.warp(block.timestamp + 2 days); // Move to epoch 1
        vm.prank(user1);
        token.mintPoVWReward(user1, 100, 1);
        
        // Now try to mint for future epoch (should fail)
        uint256 currentEpoch = token.getCurrentEpoch();
        vm.prank(user1);
        vm.expectRevert("Invalid epoch");
        token.mintPoVWReward(user1, 1000, currentEpoch + 10);
    }

    function test_EpochProgression() public view {
        // At deployment, current epoch should be 0
        uint256 currentEpoch = token.getCurrentEpoch();
        assertEq(currentEpoch, 0);
        
        // Check epoch start time
        if (token.deploymentTime() > 0) {
            uint256 epochStartTime = token.getEpochStartTime(1);
            assertTrue(epochStartTime > block.timestamp);
        }
    }

    function test_SupplyProgression() public {
        // Setup inflation minting
        vm.startPrank(owner);
        IAccessControl(address(token)).grantRole(POVW_MINTER_ROLE, user1);
        IAccessControl(address(token)).grantRole(STAKING_MINTER_ROLE, user2);
        vm.stopPrank();

        // Complete initial minting to get to 1B supply
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        recipients[0] = user3;
        amounts[0] = MINTER1_AMOUNT;
        vm.prank(initialMinter1);
        token.initialMint(recipients, amounts);

        recipients[0] = user4;
        amounts[0] = MINTER2_AMOUNT;
        vm.prank(initialMinter2);
        token.initialMint(recipients, amounts);

        assertEq(token.totalSupply(), TOTAL_SUPPLY);

        // Warp time and mint inflation
        vm.warp(block.timestamp + 4 days); // 2 epochs
        
        // Get current epoch (deploymentTime gets initialized on first mint call)
        uint256 epoch = token.getCurrentEpoch();
        if (epoch == 0) epoch = 1; // Use epoch 1 if deploymentTime not set yet
        uint256 povwAllocation = token.getPoVWAllocationForEpoch(epoch);
        uint256 stakingAllocation = token.getStakingAllocationForEpoch(epoch);

        vm.prank(user1);
        token.mintPoVWReward(user1, povwAllocation, epoch);

        vm.prank(user2);
        token.mintStakingReward(user2, stakingAllocation, epoch);

        // Total supply should have increased
        uint256 newTotalSupply = token.totalSupply();
        assertEq(newTotalSupply, TOTAL_SUPPLY + povwAllocation + stakingAllocation);
        assertTrue(newTotalSupply > TOTAL_SUPPLY);
    }

    function test_RolePermissions() public {
        // Only admin can grant inflation roles
        vm.prank(user1);
        vm.expectRevert();
        IAccessControl(address(token)).grantRole(POVW_MINTER_ROLE, user2);

        vm.prank(user1);
        vm.expectRevert();
        IAccessControl(address(token)).grantRole(STAKING_MINTER_ROLE, user2);

        // Admin can grant roles
        vm.startPrank(owner);
        IAccessControl(address(token)).grantRole(POVW_MINTER_ROLE, user1);
        IAccessControl(address(token)).grantRole(STAKING_MINTER_ROLE, user2);
        vm.stopPrank();

        assertTrue(IAccessControl(address(token)).hasRole(POVW_MINTER_ROLE, user1));
        assertTrue(IAccessControl(address(token)).hasRole(STAKING_MINTER_ROLE, user2));

        // Roles are separate
        assertFalse(IAccessControl(address(token)).hasRole(STAKING_MINTER_ROLE, user1));
        assertFalse(IAccessControl(address(token)).hasRole(POVW_MINTER_ROLE, user2));
    }
}
