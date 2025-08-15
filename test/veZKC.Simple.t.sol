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
    uint256 constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 constant AMOUNT = 10_000 * 10**18;
    
    function setUp() public {
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
        
        vm.startPrank(admin);
        zkc.grantRole(zkc.MINTER_ROLE(), admin);
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT;
        zkc.initialMint(recipients, amounts);
        vm.stopPrank();
        
        vm.prank(alice);
        zkc.approve(address(veToken), type(uint256).max);
    }
    
    function testBasicStakeAndVotes() public {
        uint256 beforeVotes = veToken.getVotes(alice);
        assertEq(beforeVotes, 0);

        // Alice stakes for 30 weeks
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 30 weeks);

        (uint256 amount, uint256 expiry) = veToken.getStakedAmountAndExpiry(alice);
        assertEq(amount, AMOUNT);
        // Expiry should be equal or rounded down to the nearest week.
        assertLe(expiry, block.timestamp + 30 weeks);
        
        // Check that getVotes works and returns some power
        uint256 votes = veToken.getVotes(alice);
        assertGt(votes, 0, "Should have some voting power");
        
        // Move forward and check decay
        vm.warp(expiry - 15 weeks);
        uint256 decayedVotes = veToken.getVotes(alice);
        assertLt(decayedVotes, votes, "Voting power should decay");

        // Check that voting power just before expiry is > 0
        vm.warp(expiry - 1);
        uint256 votesBeforeExpiry = veToken.getVotes(alice);
        assertGt(votesBeforeExpiry, 0, "Should have some voting power");
        assertLt(votesBeforeExpiry, decayedVotes, "Voting power should increase");

        // Check that voting power is 0 after expiry
        vm.warp(expiry);
        uint256 votesAfterExpiry = veToken.getVotes(alice);
        assertEq(votesAfterExpiry, 0, "Voting power should be 0 after expiry");
        
        // Check that votes don't go negative after expiry
        vm.warp(expiry + 1 weeks); // Past expiry
        uint256 expiredVotes = veToken.getVotes(alice);
        assertEq(expiredVotes, 0, "Expired votes should be 0");
    }
}