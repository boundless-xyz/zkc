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
}
