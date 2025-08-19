// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "../src/veZKC.sol";
// import "../src/ZKC.sol";
// import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// contract veZKCDelegationTest is Test {
//     veZKC public veToken;
//     ZKC public zkc;
    
//     address public admin = makeAddr("admin");
//     address public alice = makeAddr("alice");
//     address public bob = makeAddr("bob");
//     uint256 constant AMOUNT = 1000 ether;
    
//     function setUp() public {
//         vm.startPrank(admin);
        
//         // Deploy ZKC with proxy
//         ZKC zkcImpl = new ZKC();
//         bytes memory zkcInitData = abi.encodeWithSelector(
//             ZKC.initialize.selector,
//             admin, admin, AMOUNT * 100, AMOUNT * 100, admin
//         );
//         zkc = ZKC(address(new ERC1967Proxy(address(zkcImpl), zkcInitData)));
        
//         // Deploy veZKC with proxy
//         veZKC veImpl = new veZKC();
//         bytes memory veInitData = abi.encodeWithSelector(
//             veZKC.initialize.selector,
//             address(zkc),
//             admin
//         );
//         veToken = veZKC(address(new ERC1967Proxy(address(veImpl), veInitData)));
        
//         vm.stopPrank();
        
//         // Setup test accounts
//         vm.startPrank(admin);
//         zkc.grantRole(zkc.MINTER_ROLE(), admin);
//         zkc.mint(alice, AMOUNT * 10);
//         zkc.mint(bob, AMOUNT * 10);
//         vm.stopPrank();
        
//         vm.prank(alice);
//         zkc.approve(address(veToken), type(uint256).max);
//         vm.prank(bob);
//         zkc.approve(address(veToken), type(uint256).max);
//     }
    
//     function testDelegation() public {
//         vm.skip(true);
//         // Alice stakes and should auto-delegate to self
//         vm.prank(alice);
//         uint256 aliceTokenId = veToken.stake(AMOUNT, block.timestamp + 52 weeks);
        
//         // Bob needs an active position to receive delegation
//         vm.prank(bob);
//         uint256 bobTokenId = veToken.stake(AMOUNT, block.timestamp + 52 weeks); // Bob locks for same duration
        
//         // Check initial state
//         assertEq(veToken.delegates(alice), alice, "Should auto-delegate to self");
//         assertEq(veToken.delegates(bob), bob, "Bob should auto-delegate to self");
        
//         // Voting power is based on time-weighted formula
//         uint256 aliceInitialVotes = veToken.getVotes(alice);
//         uint256 bobInitialVotes = veToken.getVotes(bob);
        
//         // Alice's voting power: AMOUNT * 52 weeks / 52 weeks = AMOUNT (approximately)
//         assertGt(aliceInitialVotes, 0, "Alice should have voting power");
//         assertLt(aliceInitialVotes, AMOUNT, "Alice's votes should be less than AMOUNT due to time decay");
        
//         // Bob's voting power: AMOUNT * 52 weeks / 52 weeks = AMOUNT (approximately)
//         assertGt(bobInitialVotes, 0, "Bob should have voting power");
        
//         // Alice delegates to Bob (locks already match, no extension needed)
//         vm.prank(alice);
//         veToken.delegate(bob);
        
//         assertEq(veToken.delegates(alice), bob, "Alice should delegate to Bob");
        
//         // After delegation:
//         // - Alice's voting power goes to Bob
//         assertEq(veToken.getVotes(alice), 0, "Alice should have 0 votes after delegating");
        
//         // Bob should now have his own votes plus Alice's delegated votes
//         uint256 bobVotesAfter = veToken.getVotes(bob);
//         assertGt(bobVotesAfter, bobInitialVotes, "Bob should have more votes after receiving delegation");
        
//         // Both locks should have same end time (they already did)
//         (uint256 aliceAmount, uint256 aliceLockEnd) = veToken.locks(aliceTokenId);
//         (uint256 bobAmount, uint256 bobLockEnd) = veToken.locks(bobTokenId);
//         assertEq(aliceLockEnd, bobLockEnd, "Both locks should have same end time");
//     }
// }