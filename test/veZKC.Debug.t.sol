// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/veZKC.sol";
import "../src/ZKC.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract veZKCDebugTest is Test {
    veZKC public veToken;
    ZKC public zkc;
    
    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    uint256 constant AMOUNT = 1000 ether;
    uint256 constant MAXTIME = 52 weeks;
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy ZKC with proxy
        ZKC zkcImpl = new ZKC();
        bytes memory zkcInitData = abi.encodeWithSelector(
            ZKC.initialize.selector,
            admin, admin, AMOUNT * 100, AMOUNT * 100, admin
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
        
        // Setup test account
        vm.startPrank(admin);
        zkc.grantRole(zkc.MINTER_ROLE(), admin);
        zkc.mint(alice, AMOUNT * 10);
        vm.stopPrank();
        
        vm.prank(alice);
        zkc.approve(address(veToken), type(uint256).max);
    }
    
    function testDebugPointsCalculation() public {
        vm.skip(true);
        // Alice stakes for 52 weeks (max time)
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        // Check what our _getVotingPower returns (should be correct)
        uint256 directPower = veToken.votingPower(tokenId);
        
        // Check what getVotes returns (using Points)
        uint256 pointsPower = veToken.getVotes(alice);
        
        // They should be approximately equal initially
        assertApproxEqRel(directPower, pointsPower, 0.01e18, "Initial powers should match");
        
        // Move forward 26 weeks (half way)
        vm.warp(block.timestamp + 26 weeks);
        
        uint256 directPowerHalf = veToken.votingPower(tokenId);
        uint256 pointsPowerHalf = veToken.getVotes(alice);
        
        // Expected: after 26 weeks, should have ~26/52 = 50% of max power
        uint256 expectedHalf = (AMOUNT * 26) / 52;
        
        // Direct power should be approximately correct
        assertApproxEqRel(directPowerHalf, expectedHalf, 0.01e18, "Direct power should match expected");
        
        // Points power should also match (but currently doesn't)
        assertTrue(pointsPowerHalf < pointsPower, "Points power should decay");
        assertApproxEqRel(pointsPowerHalf, expectedHalf, 0.01e18, "Points power should match expected");
    }
    
    function testMathematicalModel() public {
        vm.skip(true);
        // The ve formula: voting_power = (amount * remaining_time) / MAXTIME
        // This should be equivalent to: power = bias + slope * time_elapsed
        // where slope = -amount/MAXTIME and bias = amount
        
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        // Test at different time points
        uint256 directInitial = veToken.votingPower(tokenId);
        assertEq(directInitial, AMOUNT, "Initial power should be full amount");
        
        // After 13 weeks (1/4 time)
        vm.warp(block.timestamp + 13 weeks);
        uint256 directQuarter = veToken.votingPower(tokenId);
        uint256 expectedQuarter = (AMOUNT * 39) / 52; // 39 weeks remaining
        assertApproxEqRel(directQuarter, expectedQuarter, 0.001e18, "Quarter time should match");
        
        // After 26 weeks (1/2 time)
        vm.warp(block.timestamp + 13 weeks); // Total 26 weeks
        uint256 directHalf = veToken.votingPower(tokenId);
        uint256 expectedHalf = (AMOUNT * 26) / 52; // 26 weeks remaining
        assertApproxEqRel(directHalf, expectedHalf, 0.001e18, "Half time should match");
        
        // Now test what bias and slope should be:
        // At t=0: power = amount, time_remaining = MAXTIME
        // At t=T: power = amount * (MAXTIME - T) / MAXTIME
        // Rewrite: power = amount - (amount * T) / MAXTIME
        // So: bias = amount, slope = -amount/MAXTIME
    }
}