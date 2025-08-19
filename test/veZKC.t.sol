// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/veZKC.sol";
import "../src/ZKC.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../src/libraries/Constants.sol";

contract veZKCTest is Test {
    veZKC public veToken;
    ZKC public zkc;
    
    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant AMOUNT = 10_000 * 10**18;

    
    function deployContracts() internal {
        vm.startPrank(admin);
        
        // Deploy ZKC with proxy
        ZKC zkcImpl = new ZKC();
        bytes memory zkcInitData = abi.encodeWithSelector(
            ZKC.initialize.selector,
            admin, // initialMinter1
            address(0), // initialMinter2
            INITIAL_SUPPLY,
            0,
            admin // owner
        );
        zkc = ZKC(address(new ERC1967Proxy(address(zkcImpl), zkcInitData)));
        zkc.initializeV2();
        
        // Deploy veZKC with proxy
        veZKC veImpl = new veZKC();
        bytes memory veInitData = abi.encodeWithSelector(
            veZKC.initialize.selector,
            address(zkc),
            admin
        );
        veToken = veZKC(address(new ERC1967Proxy(address(veImpl), veInitData)));

        vm.stopPrank();
    }
    
    function setupTokens() internal {
        vm.startPrank(admin);
        zkc.grantRole(zkc.MINTER_ROLE(), admin);
        
        // Mint tokens to test accounts
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = AMOUNT * 10;
        amounts[1] = AMOUNT * 10;
        amounts[2] = AMOUNT * 10;
        
        zkc.initialMint(recipients, amounts);
        vm.stopPrank();
        
        // Approve veToken for all users
        vm.prank(alice);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(bob);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(charlie);
        zkc.approve(address(veToken), type(uint256).max);
    }
    
    function setUp() public virtual {
        // Align timestamp to week boundary BEFORE deploying contracts
        // This ensures all initial contract state is on week boundaries
        uint256 currentTime = block.timestamp;
        uint256 weekBoundary = (currentTime / (1 weeks)) * (1 weeks);
        if (weekBoundary < currentTime) {
            weekBoundary += 1 weeks;
        }
        vm.warp(weekBoundary);
        
        deployContracts();
        setupTokens();
    }

    // Helper function to create permit signatures
    function _createPermitSignature(
        uint256 privateKey,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = zkc.DOMAIN_SEPARATOR();
        uint256 nonce = zkc.nonces(owner);
        
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        
        return vm.sign(privateKey, digest);
    }
    
}