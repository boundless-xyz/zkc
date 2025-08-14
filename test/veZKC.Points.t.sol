// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/veZKC.sol";
import "../src/ZKC.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract veZKCPointsTest is Test {
    veZKC public veToken;
    ZKC public zkc;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    uint256 constant AMOUNT = 1000 ether;
    uint256 constant WEEK = 1 weeks;
    uint256 constant MAXTIME = 52 * WEEK;
    
    function setUp() public {
        // Deploy ZKC token
        ZKC zkcImpl = new ZKC();
        bytes memory initData = abi.encodeWithSelector(
            ZKC.initialize.selector,
            address(this),
            address(this),
            address(this)
        );
        ERC1967Proxy zkcProxy = new ERC1967Proxy(address(zkcImpl), initData);
        zkc = ZKC(address(zkcProxy));
        
        // Deploy veZKC
        veZKC veImpl = new veZKC();
        bytes memory veInitData = abi.encodeWithSelector(
            veZKC.initialize.selector,
            address(zkc),
            address(this)
        );
        ERC1967Proxy veProxy = new ERC1967Proxy(address(veImpl), veInitData);
        veToken = veZKC(address(veProxy));
        
        // Setup test accounts with ZKC
        zkc.mint(alice, AMOUNT * 10);
        zkc.mint(bob, AMOUNT * 10);
        zkc.mint(charlie, AMOUNT * 10);
        
        vm.prank(alice);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(bob);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(charlie);
        zkc.approve(address(veToken), type(uint256).max);
    }
    
    // Test 1: getVotes returns properly decayed amounts over time
    function testGetVotesDecaysOverTime() public {
        // Alice stakes for 52 weeks (max time)
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        // Initial voting power should be AMOUNT (max power for max time)
        uint256 initialPower = veToken.getVotes(alice);
        assertApproxEqRel(initialPower, AMOUNT, 0.01e18, "Initial power should be ~AMOUNT");
        
        // After 26 weeks (half time), power should be ~50%
        vm.warp(block.timestamp + 26 weeks);
        uint256 halfTimePower = veToken.getVotes(alice);
        assertApproxEqRel(halfTimePower, AMOUNT / 2, 0.01e18, "Half-time power should be ~50%");
        
        // After 52 weeks (lock expired), power should be 0
        vm.warp(block.timestamp + 26 weeks); // Total 52 weeks
        uint256 expiredPower = veToken.getVotes(alice);
        assertEq(expiredPower, 0, "Expired lock should have 0 power");
    }
    
    // Test 2: getPastVotes returns correct historical values
    function testGetPastVotesHistoricalAccuracy() public {
        // Record initial timestamp
        uint256 t0 = block.timestamp;
        
        // Alice stakes at t0
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        // Move forward and record checkpoints
        vm.warp(t0 + 10 weeks);
        uint256 t1 = block.timestamp;
        
        vm.warp(t0 + 20 weeks);
        uint256 t2 = block.timestamp;
        
        // Bob stakes at t2
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + 26 weeks);
        
        vm.warp(t0 + 30 weeks);
        
        // Query historical values
        uint256 alicePowerAtT1 = veToken.getPastVotes(alice, t1);
        uint256 expectedAtT1 = AMOUNT * (52 - 10) / 52; // 42/52 of initial
        assertApproxEqRel(alicePowerAtT1, expectedAtT1, 0.01e18, "Historical power at t1 incorrect");
        
        uint256 alicePowerAtT2 = veToken.getPastVotes(alice, t2);
        uint256 expectedAtT2 = AMOUNT * (52 - 20) / 52; // 32/52 of initial
        assertApproxEqRel(alicePowerAtT2, expectedAtT2, 0.01e18, "Historical power at t2 incorrect");
        
        // Bob should have 0 power at t1 (before staking)
        uint256 bobPowerAtT1 = veToken.getPastVotes(bob, t1);
        assertEq(bobPowerAtT1, 0, "Bob should have 0 power before staking");
    }
    
    // Test 3: Delegation updates Points correctly
    function testDelegationWithPointsSystem() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
        // Bob stakes
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + 26 weeks);
        
        // Initial: everyone self-delegates
        uint256 aliceInitial = veToken.getVotes(alice);
        uint256 bobInitial = veToken.getVotes(bob);
        
        // Bob delegates to Alice
        vm.prank(bob);
        veToken.delegate(alice);
        
        // Alice should have combined voting power
        uint256 aliceCombined = veToken.getVotes(alice);
        assertApproxEqRel(aliceCombined, aliceInitial + bobInitial, 0.01e18, "Delegation failed");
        
        // Bob should have 0 votes (delegated away)
        uint256 bobAfterDelegate = veToken.getVotes(bob);
        assertEq(bobAfterDelegate, 0, "Bob should have 0 votes after delegation");
        
        // Move forward in time - decay should still work
        vm.warp(block.timestamp + 13 weeks);
        
        uint256 aliceDecayed = veToken.getVotes(alice);
        uint256 expectedAlice = AMOUNT * 39 / 52 + AMOUNT * 13 / 52; // Alice: 39/52, Bob: 13/52
        assertApproxEqRel(aliceDecayed, expectedAlice, 0.01e18, "Delegated decay incorrect");
    }
    
    // Test 4: getTotalVotes with multiple users and decay
    function testGetTotalVotesWithDecay() public {
        // Multiple users stake at different times
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 52 weeks); // Full year
        
        uint256 totalAfterAlice = veToken.getTotalVotes();
        assertApproxEqRel(totalAfterAlice, AMOUNT, 0.01e18, "Total after Alice incorrect");
        
        vm.warp(block.timestamp + 10 weeks);
        
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + 26 weeks); // Half year
        
        // Total should be Alice's decayed + Bob's initial
        uint256 aliceDecayed = AMOUNT * 42 / 52;
        uint256 bobInitial = AMOUNT * 26 / 52;
        uint256 expectedTotal = aliceDecayed + bobInitial;
        
        uint256 totalAfterBob = veToken.getTotalVotes();
        assertApproxEqRel(totalAfterBob, expectedTotal, 0.01e18, "Total after Bob incorrect");
        
        // Fast forward to when Bob's lock expires
        vm.warp(block.timestamp + 26 weeks);
        
        // Only Alice should have remaining power
        uint256 aliceRemaining = AMOUNT * 16 / 52;
        uint256 totalAtBobExpiry = veToken.getTotalVotes();
        assertApproxEqRel(totalAtBobExpiry, aliceRemaining, 0.01e18, "Total at Bob expiry incorrect");
    }
    
    // Test 5: Slope changes are properly scheduled and applied
    function testSlopeChangesAtExpiry() public {
        // Alice stakes for 8 weeks
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 8 weeks);
        
        // Bob stakes for 12 weeks  
        vm.prank(bob);
        veToken.stake(AMOUNT, block.timestamp + 12 weeks);
        
        // Check slope changes are scheduled
        uint256 aliceExpiry = ((block.timestamp + 8 weeks) / WEEK) * WEEK;
        uint256 bobExpiry = ((block.timestamp + 12 weeks) / WEEK) * WEEK;
        
        int128 aliceSlopeChange = veToken.slopeChanges(aliceExpiry);
        int128 bobSlopeChange = veToken.slopeChanges(bobExpiry);
        
        // Slope changes should be positive (making global slope less negative)
        assertTrue(aliceSlopeChange > 0, "Alice slope change should be positive");
        assertTrue(bobSlopeChange > 0, "Bob slope change should be positive");
        
        // Move to just before Alice expiry
        vm.warp(aliceExpiry - 1);
        uint256 totalBeforeExpiry = veToken.getTotalVotes();
        
        // Move past Alice expiry
        vm.warp(aliceExpiry + 1);
        uint256 totalAfterExpiry = veToken.getTotalVotes();
        
        // Total should decrease more significantly after expiry
        assertTrue(totalAfterExpiry < totalBeforeExpiry, "Total should decrease after expiry");
    }
    
    // Test 6: Adding to stake updates Points correctly
    function testAddToStakeUpdatesPoints() public {
        // Alice stakes initially
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + 26 weeks);
        
        uint256 initialPower = veToken.getVotes(alice);
        
        // Move forward 10 weeks
        vm.warp(block.timestamp + 10 weeks);
        
        uint256 decayedPower = veToken.getVotes(alice);
        assertLt(decayedPower, initialPower, "Power should decay over time");
        
        // Add more stake
        vm.prank(alice);
        veToken.addToStake(tokenId, AMOUNT);
        
        // Power should increase but still be based on remaining time (16 weeks)
        uint256 afterAddPower = veToken.getVotes(alice);
        uint256 expectedPower = (AMOUNT * 2) * 16 / 52; // Double amount, 16 weeks left
        assertApproxEqRel(afterAddPower, expectedPower, 0.01e18, "Power after add incorrect");
    }
    
    // Test 7: Lock extension updates Points and slopes
    function testLockExtensionUpdatesPoints() public {
        // Alice stakes for minimum time
        vm.prank(alice);
        uint256 tokenId = veToken.stake(AMOUNT, block.timestamp + 4 weeks);
        
        uint256 initialPower = veToken.getVotes(alice);
        uint256 expectedInitial = AMOUNT * 4 / 52;
        assertApproxEqRel(initialPower, expectedInitial, 0.01e18, "Initial 4-week power incorrect");
        
        // Extend lock by 48 weeks (to max 52 weeks total)
        vm.prank(alice);
        (, uint256 currentLockEnd) = veToken.locks(tokenId);
        uint256 newLockEndTime = currentLockEnd + 48 weeks;
        veToken.extendLockToTime(tokenId, newLockEndTime);
        
        uint256 extendedPower = veToken.getVotes(alice);
        assertApproxEqRel(extendedPower, AMOUNT, 0.01e18, "Extended power should be ~AMOUNT");
        
        // Check slope change is updated
        uint256 newExpiry = ((block.timestamp + 52 weeks) / WEEK) * WEEK;
        int128 slopeChange = veToken.slopeChanges(newExpiry);
        assertTrue(slopeChange > 0, "Extended slope change should be scheduled");
    }
    
    // Test 8: Ensure votes can't go negative
    function testVotesNeverNegative() public {
        // Stake and let it expire
        vm.prank(alice);
        veToken.stake(AMOUNT, block.timestamp + 4 weeks);
        
        // Move well past expiry
        vm.warp(block.timestamp + 10 weeks);
        
        uint256 expiredVotes = veToken.getVotes(alice);
        assertEq(expiredVotes, 0, "Expired votes should be 0, not negative");
        
        uint256 totalVotes = veToken.getTotalVotes();
        assertEq(totalVotes, 0, "Total votes should be 0 when all expired");
    }
}