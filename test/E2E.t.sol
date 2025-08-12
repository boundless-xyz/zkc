// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ZKC} from "../src/ZKC.sol";
import {veZKC} from "../src/veZKC.sol";
import {StakingVault} from "../src/StakingVault.sol";

contract E2ETest is Test {
    ZKC public zkc;
    veZKC public veZkcToken;
    StakingVault public stakingVault;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    
    uint256 constant INITIAL_MINT_AMOUNT = 1000000e18;
    uint256 constant STAKE_AMOUNT = 1000e18;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ZKC token
        ZKC zkcImpl = new ZKC();
        bytes memory zkcInitData = abi.encodeWithSelector(
            ZKC.initialize.selector,
            admin, // initialMinter1
            admin, // initialMinter2
            INITIAL_MINT_AMOUNT,
            INITIAL_MINT_AMOUNT,
            admin  // owner
        );
        zkc = ZKC(address(new ERC1967Proxy(address(zkcImpl), zkcInitData)));

        // Mint initial tokens
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = STAKE_AMOUNT * 10;
        amounts[1] = STAKE_AMOUNT * 10;
        amounts[2] = STAKE_AMOUNT * 10;
        
        zkc.initialMint(recipients, amounts);

        // Deploy veZKC
        veZKC veZkcImpl = new veZKC();
        veZkcToken = veZKC(address(new ERC1967Proxy(
            address(veZkcImpl), 
            abi.encodeWithSelector(veZKC.initialize.selector, address(0), admin)
        )));

        // Deploy StakingVault
        StakingVault vaultImpl = new StakingVault();
        stakingVault = StakingVault(address(new ERC1967Proxy(
            address(vaultImpl), 
            abi.encodeWithSelector(
                StakingVault.initialize.selector,
                address(zkc),
                address(veZkcToken),
                admin
            )
        )));

        // Grant roles to StakingVault
        veZkcToken.grantRole(veZkcToken.STAKING_VAULT_ROLE(), address(stakingVault));

        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(zkc.balanceOf(alice), STAKE_AMOUNT * 10);
        assertEq(veZkcToken.balanceOf(alice), 0);
    }

    function test_Staking() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks = 1 year

        // Check balances
        assertEq(zkc.balanceOf(alice), STAKE_AMOUNT * 9); // 10 - 1
        assertEq(veZkcToken.balanceOf(alice), 1);
        assertEq(veZkcToken.ownerOf(tokenId), alice);

        // Check voting power (should be full amount for max lock)
        uint256 expectedPower = STAKE_AMOUNT; // No multipliers, just amount for max lock
        assertEq(veZkcToken.votingPower(tokenId), expectedPower);
        assertEq(veZkcToken.getCurrentVotingPower(alice), expectedPower);
        
        vm.stopPrank();
    }

    function test_VotingPowerDecay() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks = 1 year

        // Check initial voting power (full amount for max lock)
        uint256 initialPower = veZkcToken.votingPower(tokenId);
        assertEq(initialPower, STAKE_AMOUNT);

        // Fast forward 26 weeks (half the lock period)
        vm.warp(block.timestamp + 26 weeks);

        // Voting power should be approximately half
        uint256 halfTimePower = veZkcToken.votingPower(tokenId);
        assertApproxEqRel(halfTimePower, STAKE_AMOUNT / 2, 0.01e18); // 1% tolerance

        // Fast forward to end of lock period
        vm.warp(block.timestamp + 26 weeks);

        // Voting power should be zero
        uint256 endPower = veZkcToken.votingPower(tokenId);
        assertEq(endPower, 0);
        
        vm.stopPrank();
    }

    function test_AddStakePreservesDecay() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT * 2);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks

        // Fast forward 26 weeks (half the lock period)
        vm.warp(block.timestamp + 26 weeks);

        uint256 powerBeforeAdd = veZkcToken.votingPower(tokenId);
        console.log("Power before adding stake:", powerBeforeAdd);

        // Add more stake
        stakingVault.addToStake(tokenId, STAKE_AMOUNT);

        uint256 powerAfterAdd = veZkcToken.votingPower(tokenId);
        console.log("Power after adding stake:", powerAfterAdd);

        // Curve behavior: both old and new tokens get power based on REMAINING time
        // total: 2000 ZKC × 0.5 remaining time = 1000 power
        uint256 expectedPower = STAKE_AMOUNT * 2 / 2; // Total amount × remaining time ratio
        assertApproxEqRel(powerAfterAdd, expectedPower, 0.01e18); // 1% tolerance

        // Total amount should be increased in the NFT
        (uint256 totalAmount,,) = veZkcToken.locks(tokenId);
        assertEq(totalAmount, STAKE_AMOUNT * 2);
        
        vm.stopPrank();
    }

    function test_DirectUnstake() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks = 1 year

        // Try to unstake immediately (should fail - lock not expired)
        vm.expectRevert("Lock has not expired yet");
        stakingVault.unstake(tokenId);

        // Fast forward to lock expiry
        vm.warp(block.timestamp + 52 weeks);

        // Now should be able to unstake directly
        uint256 balanceBefore = zkc.balanceOf(alice);
        stakingVault.unstake(tokenId);
        uint256 balanceAfter = zkc.balanceOf(alice);

        assertEq(balanceAfter - balanceBefore, STAKE_AMOUNT);
        
        // NFT should no longer exist
        vm.expectRevert();
        veZkcToken.ownerOf(tokenId);

        vm.stopPrank();
    }

    function test_NonTransferableNFT() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks

        vm.stopPrank();

        // Try to transfer NFT (should fail)
        vm.prank(alice);
        vm.expectRevert("veZKC: Non-transferable");
        veZkcToken.transferFrom(alice, bob, tokenId);
    }

    function test_BurnExpiredNFT() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks

        vm.stopPrank();

        // Fast forward past expiry
        vm.warp(block.timestamp + 52 weeks + 1);

        // Anyone should be able to burn expired NFT
        vm.prank(bob);
        stakingVault.burnExpiredNFT(tokenId);

        // NFT should no longer exist
        vm.expectRevert();
        veZkcToken.ownerOf(tokenId);
    }

    function test_IVotesInterface() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // Max lock weeks
        
        // Test delegation
        assertEq(veZkcToken.delegates(alice), alice); // Auto-delegates to self
        uint256 expectedPower = STAKE_AMOUNT; // No multipliers, just amount for max lock
        assertEq(veZkcToken.getVotes(alice), expectedPower);
        
        // Test delegation to another address
        veZkcToken.delegate(bob);
        assertEq(veZkcToken.delegates(alice), bob);
        assertEq(veZkcToken.getVotes(alice), expectedPower); // Alice's votes still follow her delegation target
        assertEq(veZkcToken.getVotes(bob), expectedPower); // Bob now has Alice's voting power
        
        // Test total supply
        assertEq(veZkcToken.getTotalVotes(), expectedPower);
        
        vm.stopPrank();
        
        // Bob stakes and delegates to self
        vm.startPrank(bob);
        zkc.approve(address(stakingVault), STAKE_AMOUNT * 2);
        uint256 bobTokenId = stakingVault.stake(STAKE_AMOUNT * 2, 26); // 26 weeks = half max
        
        // Bob's voting power should be auto-delegated to self already
        uint256 bobOwnPower = STAKE_AMOUNT; // (2000 * 26) / 52 = 1000
        
        // Total should be Alice's delegated power + Bob's own power
        uint256 totalExpectedPower = expectedPower + bobOwnPower;
        
        assertEq(veZkcToken.getVotes(bob), totalExpectedPower);
        assertEq(veZkcToken.getTotalVotes(), totalExpectedPower);
        
        vm.stopPrank();
    }
    
    function test_IVotesHistoricalPower() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // Max lock weeks
        
        // Record initial block and voting power
        uint256 initialBlock = block.number;
        uint256 expectedPower = STAKE_AMOUNT; // No multipliers, just amount for max lock
        assertEq(veZkcToken.getVotes(alice), expectedPower);
        
        // Fast forward some blocks
        vm.roll(block.number + 100);
        
        // Voting power should be the same (no time-based decay in checkpoints)
        assertEq(veZkcToken.getVotes(alice), expectedPower);
        
        // Check historical voting power
        assertEq(veZkcToken.getPastVotes(alice, initialBlock), expectedPower);
        
        // Add more stake to change voting power
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        stakingVault.addToStake(tokenId, STAKE_AMOUNT);
        
        uint256 newBlock = block.number;
        uint256 newExpectedPower = STAKE_AMOUNT * 2; // Double amount, no multipliers
        
        // Fast forward more blocks
        vm.roll(block.number + 100);
        
        // Current power should reflect new amount
        assertEq(veZkcToken.getVotes(alice), newExpectedPower);
        
        // Historical power should show old amount
        assertEq(veZkcToken.getPastVotes(alice, initialBlock), expectedPower);
        assertEq(veZkcToken.getPastVotes(alice, newBlock), newExpectedPower);
        
        // Test total supply history
        assertEq(veZkcToken.getPastTotalSupply(initialBlock), expectedPower);
        assertEq(veZkcToken.getPastTotalSupply(newBlock), newExpectedPower);
        
        vm.stopPrank();
    }

    function test_RewardPowerInterface() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // Max lock weeks

        // Note: veZKC auto-delegates to self in _updateVotingPower during minting
        // Check reward power matches voting power (both use same formula now)
        uint256 expectedInitialPower = STAKE_AMOUNT; // No multipliers, just amount for max lock
        assertEq(veZkcToken.getRewardPower(alice), expectedInitialPower);
        assertEq(veZkcToken.getVotes(alice), expectedInitialPower);
        assertEq(veZkcToken.getRewardPower(alice), expectedInitialPower);
        assertEq(veZkcToken.getCurrentVotingPower(alice), expectedInitialPower);

        // Fast forward and check decay affects both equally
        vm.warp(block.timestamp + 26 weeks); // Half the lock time

        // Note: getVotes() returns checkpointed values, which don't auto-update with time decay
        // The actual individual voting power decays correctly
        uint256 actualRewardPower = veZkcToken.getRewardPower(alice);
        uint256 actualVotingPower = veZkcToken.getCurrentVotingPower(alice);
        uint256 checkpointedVotes = veZkcToken.getVotes(alice);
        
        console.log("After 104 weeks:");
        console.log("  actualRewardPower:", actualRewardPower);
        console.log("  actualVotingPower:", actualVotingPower);  
        console.log("  checkpointedVotes:", checkpointedVotes);
        console.log("  expectedHalfway:", expectedInitialPower / 2);
        
        // Both should decay to approximately 50% of initial
        uint256 expectedHalfwayPower = expectedInitialPower / 2;
        assertApproxEqRel(actualRewardPower, expectedHalfwayPower, 0.01e18);
        assertApproxEqRel(actualVotingPower, expectedHalfwayPower, 0.01e18);
        
        // They should be equal since they use the same formula
        assertEq(actualRewardPower, actualVotingPower);

        vm.stopPrank();
    }

    function test_MultipleStakePositions() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT * 3);
        
        // Create first position with 52 weeks (1 year)
        uint256 tokenId1 = stakingVault.stake(STAKE_AMOUNT, 52);
        
        // Fast forward 13 weeks (3 months)
        vm.warp(block.timestamp + 13 weeks);
        
        // Create second position with 52 weeks
        uint256 tokenId2 = stakingVault.stake(STAKE_AMOUNT, 52);
        
        // Fast forward another 13 weeks
        vm.warp(block.timestamp + 13 weeks);
        
        // Create third position with 52 weeks
        uint256 tokenId3 = stakingVault.stake(STAKE_AMOUNT, 52);

        // Check individual voting powers
        uint256 power1 = veZkcToken.votingPower(tokenId1); // ~26 weeks remaining
        uint256 power2 = veZkcToken.votingPower(tokenId2); // ~39 weeks remaining  
        uint256 power3 = veZkcToken.votingPower(tokenId3); // ~52 weeks remaining

        console.log("Token 1 power (~26w remaining):", power1);
        console.log("Token 2 power (~39w remaining):", power2);
        console.log("Token 3 power (~52w remaining):", power3);

        // Token 3 should have highest power, token 1 lowest
        assertGt(power3, power2);
        assertGt(power2, power1);

        // Total voting power should be sum of all positions
        uint256 totalPower = veZkcToken.getCurrentVotingPower(alice);
        assertEq(totalPower, power1 + power2 + power3);

        vm.stopPrank();
    }

    function test_LockExtensionIncremental() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks = 1 year
        
        uint256 originalLockEnd = block.timestamp + 52 weeks;

        // Fast forward 26 weeks (6 months) - should have 26 weeks remaining
        vm.warp(block.timestamp + 26 weeks);

        uint256 powerBeforeExtend = veZkcToken.votingPower(tokenId);
        console.log("Power before extending lock:", powerBeforeExtend);
        
        // Should have ~50% power remaining (26 weeks remaining out of original 52)
        uint256 expectedPowerBefore = STAKE_AMOUNT * 26 weeks / (52 weeks);
        assertApproxEqRel(powerBeforeExtend, expectedPowerBefore, 0.01e18);

        // Extend by 1 week (now have 27 weeks total remaining)
        stakingVault.extendLockByWeeks(tokenId, 1);

        uint256 powerAfterExtend = veZkcToken.votingPower(tokenId);
        console.log("Power after extending by 1 week:", powerAfterExtend);

        // After extending by 1 week, should have power for 27 weeks remaining
        uint256 expectedPowerAfter = STAKE_AMOUNT * 27 weeks / (52 weeks);
        assertApproxEqRel(powerAfterExtend, expectedPowerAfter, 0.01e18);

        // Check that lock end was extended by 1 week
        (, uint256 lockEnd,) = veZkcToken.locks(tokenId);
        assertEq(lockEnd, originalLockEnd + 1 weeks);

        vm.stopPrank();
    }
    
    function test_LockExtensionToSpecificTime() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks = 1 year

        // Fast forward 26 weeks (6 months)
        vm.warp(block.timestamp + 26 weeks);

        // Extend to a specific end time (52 weeks from now = 1 year from now)
        uint256 newTargetEndTime = block.timestamp + 52 weeks;
        stakingVault.extendLockToTime(tokenId, newTargetEndTime);

        uint256 powerAfterExtend = veZkcToken.votingPower(tokenId);
        console.log("Power after extending to specific time:", powerAfterExtend);

        // After extending, should have power for 52 weeks remaining
        uint256 expectedPower = STAKE_AMOUNT; // 100% of max
        assertApproxEqRel(powerAfterExtend, expectedPower, 0.01e18);

        // Check that lock end was updated to target time (rounded down to week)
        (, uint256 lockEnd,) = veZkcToken.locks(tokenId);
        uint256 expectedLockEnd = (newTargetEndTime / 1 weeks) * 1 weeks; // Rounded down
        assertEq(lockEnd, expectedLockEnd);

        vm.stopPrank();
    }

    function test_MultiWeekStaking() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT * 4);
        
        // Stake with different week durations
        uint256 tokenId4 = stakingVault.stake(STAKE_AMOUNT, 4);   // 4 weeks (minimum)
        uint256 tokenId26 = stakingVault.stake(STAKE_AMOUNT, 26); // 26 weeks (~6 months)
        uint256 tokenId52 = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks (1 year)
        uint256 tokenIdMax = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks (1 year, max)
        
        // Check voting powers (natural scaling based on lock duration)
        uint256 power4 = veZkcToken.votingPower(tokenId4);     // 1000 * 4/52
        uint256 power26 = veZkcToken.votingPower(tokenId26);   // 1000 * 26/52
        uint256 power52 = veZkcToken.votingPower(tokenId52);   // 1000 * 52/52
        uint256 power52Max = veZkcToken.votingPower(tokenIdMax); // 1000 * 52/52 = 1000
        
        assertEq(power4, STAKE_AMOUNT * 4 / 52);     // ~77
        assertEq(power26, STAKE_AMOUNT * 26 / 52);   // 500
        assertEq(power52, STAKE_AMOUNT * 52 / 52);   // 1000
        assertEq(power52Max, STAKE_AMOUNT);             // 1000
        
        console.log("4 week power:", power4);
        console.log("26 week power:", power26);
        console.log("52 week power:", power52);
        console.log("52 week power:", power52Max);
        
        vm.stopPrank();
    }
    
    function test_LockWeekUpgrade() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 4); // 4 weeks minimum
        
        // Fast forward 2 weeks (halfway through 4-week lock) - 2 weeks remaining
        vm.warp(block.timestamp + 2 weeks);
        
        uint256 powerBefore = veZkcToken.votingPower(tokenId);
        console.log("Power before upgrade:", powerBefore);
        
        // Extend to max time from now (52 weeks from current timestamp)
        uint256 maxLockEndTime = block.timestamp + 52 weeks;
        stakingVault.extendLockToTime(tokenId, maxLockEndTime);
        
        uint256 powerAfter = veZkcToken.votingPower(tokenId);
        console.log("Power after upgrade:", powerAfter);
        
        // Should now have full power (amount * 52/52 = amount) - allow small precision error
        assertApproxEqRel(powerAfter, STAKE_AMOUNT, 0.01e18); // 1% tolerance
        
        // Try to reduce lock end time (should fail)
        uint256 shorterEndTime = block.timestamp + 52 weeks;
        vm.expectRevert("Can only increase lock end time");
        stakingVault.extendLockToTime(tokenId, shorterEndTime);
        
        vm.stopPrank();
    }
    
    function test_SmallIncrementalExtensions() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT);
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // 52 weeks = 1 year
        
        // Fast forward 48 weeks - should have 4 weeks remaining
        vm.warp(block.timestamp + 48 weeks);
        
        uint256 powerBefore = veZkcToken.votingPower(tokenId);
        console.log("Power with 4 weeks remaining:", powerBefore);
        
        // Expected power with 4 weeks remaining: amount * 4/52
        uint256 expectedPowerBefore = STAKE_AMOUNT * 4 / 52;
        assertApproxEqRel(powerBefore, expectedPowerBefore, 0.01e18);
        
        // Extend by just 1 week (now should have 5 weeks total remaining)
        stakingVault.extendLockByWeeks(tokenId, 1);
        
        uint256 powerAfter = veZkcToken.votingPower(tokenId);
        console.log("Power after extending by 1 week:", powerAfter);
        
        // Expected power with 5 weeks remaining: amount * 5/52
        uint256 expectedPowerAfter = STAKE_AMOUNT * 5 / 52;
        assertApproxEqRel(powerAfter, expectedPowerAfter, 0.01e18);
        
        // Verify we can extend by very small amounts multiple times
        stakingVault.extendLockByWeeks(tokenId, 1); // Now 6 weeks
        stakingVault.extendLockByWeeks(tokenId, 1); // Now 7 weeks
        
        uint256 powerAfterMultipleExtensions = veZkcToken.votingPower(tokenId);
        uint256 expectedPowerFinal = STAKE_AMOUNT * 7 / 52;
        assertApproxEqRel(powerAfterMultipleExtensions, expectedPowerFinal, 0.01e18);
        
        vm.stopPrank();
    }
    
    function test_WeekBasedSystem() public {
        vm.startPrank(alice);
        
        zkc.approve(address(stakingVault), STAKE_AMOUNT * 4);
        
        // Test that week constants are correctly returned
        assertEq(veZkcToken.MIN_LOCK_WEEKS(), 4);    // Min 4 weeks
        assertEq(veZkcToken.MAX_LOCK_WEEKS(), 52);  // Max 52 weeks
        
        // Test week conversions
        assertEq(veZkcToken.weeksToSeconds(4), 4 weeks);
        assertEq(veZkcToken.secondsToWeeks(52 weeks), 52);
        
        // Test that voting power scales with lock weeks
        uint256 tokenId = stakingVault.stake(STAKE_AMOUNT, 52); // Max lock
        
        uint256 expectedPower = STAKE_AMOUNT; // Full amount for max lock
        assertEq(veZkcToken.votingPower(tokenId), expectedPower);
        assertEq(veZkcToken.getRewardPower(alice), expectedPower);
        
        // Test minimum lock validation
        vm.expectRevert("Invalid lock weeks");
        stakingVault.stake(STAKE_AMOUNT, 3); // Below minimum
        
        // Test maximum lock validation  
        vm.expectRevert("Invalid lock weeks");
        stakingVault.stake(STAKE_AMOUNT, 53); // Above maximum
        
        vm.stopPrank();
    }
}