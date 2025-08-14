// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/veZKC.sol";
import "../src/ZKC.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract veZKCSimpleTest is Test {
    veZKC public veToken;
    ZKC public zkc;
    
    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    uint256 constant AMOUNT = 1000 ether;
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy ZKC with proxy
        ZKC zkcImpl = new ZKC();
        bytes memory zkcInitData = abi.encodeWithSelector(
            ZKC.initialize.selector,
            admin, // initialMinter1
            admin, // initialMinter2
            AMOUNT * 100,
            AMOUNT * 100,
            admin // owner
        );
        zkc = ZKC(address(new ERC1967Proxy(address(zkcImpl), zkcInitData)));
        
        // Deploy veZKC with proxy
        veZKC veImpl = new veZKC();
        bytes memory veInitData = abi.encodeWithSelector(
            veZKC.initialize.selector,
            address(zkc),
            admin
        );
        veToken = veZKC(address(new ERC1967Proxy(address(veImpl), veInitData)));
        
        vm.stopPrank();
        
        // Grant minter role to admin and mint to alice
        vm.startPrank(admin);
        zkc.grantRole(zkc.MINTER_ROLE(), admin);
        zkc.mint(alice, AMOUNT * 10);
        vm.stopPrank();
        
        vm.prank(alice);
        zkc.approve(address(veToken), type(uint256).max);
    }
    
    function testBasicStakeAndVotes() public {
        // Alice stakes for 52 weeks
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 52 * 1 weeks);
        
        // Check that getVotes works and returns some power
        uint256 votes = veToken.getVotes(alice);
        assertGt(votes, 0, "Should have some voting power");
        console.log("Initial voting power:", votes);
        
        // Move forward and check decay
        vm.warp(block.timestamp + 26 weeks);
        uint256 decayedVotes = veToken.getVotes(alice);
        assertLt(decayedVotes, votes, "Voting power should decay");
        console.log("Decayed voting power:", decayedVotes);
        
        // Check that votes don't go negative
        vm.warp(block.timestamp + 30 weeks); // Past expiry
        uint256 expiredVotes = veToken.getVotes(alice);
        assertEq(expiredVotes, 0, "Expired votes should be 0");
        console.log("Expired voting power:", expiredVotes);
    }
}