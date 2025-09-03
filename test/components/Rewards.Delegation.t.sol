// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../veZKC.t.sol";
import "../../src/interfaces/IRewards.sol";
import "../../src/interfaces/IStaking.sol";
import "../../src/interfaces/IVotes.sol";
import "../../src/libraries/Constants.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {console2} from "forge-std/Test.sol";

contract RewardsDelegationTest is veZKCTest {
    using MessageHashUtils for bytes32;
    
    address public constant CHARLIE = address(3);
    address public constant DAVE = address(4);
    
    // Test accounts with known private keys for signature tests
    uint256 constant ALICE_PK = 0xA11CE;
    uint256 constant BOB_PK = 0xB0B;
    address aliceSigner;
    address bobSigner;
    
    // EIP-712 constants
    bytes32 private constant REWARD_DELEGATION_TYPEHASH =
        keccak256("RewardDelegation(address delegatee,uint256 nonce,uint256 expiry)");
    bytes32 private constant DOMAIN_TYPEHASH = 
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public override {
        super.setUp();

        // Setup additional accounts
        deal(address(zkc), CHARLIE, AMOUNT * 10);
        deal(address(zkc), DAVE, AMOUNT * 10);

        vm.prank(CHARLIE);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(DAVE);
        zkc.approve(address(veToken), type(uint256).max);
        
        // Set up signers with known private keys for signature tests
        aliceSigner = vm.addr(ALICE_PK);
        bobSigner = vm.addr(BOB_PK);
        
        // Fund the signers
        deal(address(zkc), aliceSigner, AMOUNT * 10);
        deal(address(zkc), bobSigner, AMOUNT * 10);
        
        // Approve veToken to spend ZKC
        vm.prank(aliceSigner);
        zkc.approve(address(veToken), type(uint256).max);
        vm.prank(bobSigner);
        zkc.approve(address(veToken), type(uint256).max);
    }
    
    // Helper function to create EIP-712 digest for reward delegation
    function _createRewardDelegationDigest(
        address delegatee,
        uint256 nonce,
        uint256 expiry
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(REWARD_DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("Vote Escrowed ZK Coin")),
                keccak256(bytes("1")),
                block.chainid,
                address(veToken)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function testSelfRewardDelegationByDefault() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Check Alice delegates rewards to herself by default
        assertEq(veToken.rewardDelegates(alice), alice, "Should self-delegate rewards by default");
        assertEq(
            veToken.getStakingRewards(alice),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Should have reward power equal to stake/scalar"
        );
    }

    function testSimpleRewardDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Check delegation
        assertEq(veToken.rewardDelegates(alice), bob, "Alice should delegate rewards to Bob");
        assertEq(veToken.getStakingRewards(alice), 0, "Alice should have no reward power");
        assertEq(
            veToken.getStakingRewards(bob),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have Alice's reward power"
        );
    }

    function testRewardDelegationChangeUpdatesRewards() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);
        assertEq(
            veToken.getStakingRewards(bob),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have Alice's reward power"
        );

        // Alice re-delegates rewards to Charlie
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        assertEq(veToken.rewardDelegates(alice), CHARLIE, "Alice should delegate rewards to Charlie");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no reward power");
        assertEq(
            veToken.getStakingRewards(CHARLIE),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Charlie should have Alice's reward power"
        );
    }

    function testMultipleRewardDelegators() public {
        // Alice and Bob stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT * 2);

        // Both delegate rewards to Charlie
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);
        vm.prank(bob);
        veToken.delegateRewards(CHARLIE);

        // Charlie should have combined reward power
        uint256 expectedRewards = (AMOUNT * 3) / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getStakingRewards(CHARLIE), expectedRewards, "Charlie should have combined reward power");
        assertEq(veToken.getStakingRewards(alice), 0, "Alice should have no reward power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no reward power");
    }

    function testDelegateRewardsBackToSelf() public {
        // Alice stakes and delegates rewards to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        assertEq(
            veToken.getStakingRewards(bob),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have Alice's reward power"
        );

        // Alice delegates rewards back to herself
        vm.prank(alice);
        veToken.delegateRewards(alice);

        assertEq(veToken.rewardDelegates(alice), alice, "Alice should delegate rewards to herself");
        assertEq(
            veToken.getStakingRewards(alice),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Alice should have her reward power back"
        );
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no reward power");
    }

    function testAddToStakeWithRewardDelegation() public {
        // Alice stakes and delegates rewards to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        assertEq(
            veToken.getStakingRewards(bob),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have initial reward power"
        );

        // Alice adds to her stake
        vm.prank(alice);
        veToken.addToStake(AMOUNT);

        // Bob's reward power should increase
        assertEq(
            veToken.getStakingRewards(bob),
            (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR,
            "Bob should have increased reward power"
        );
        assertEq(veToken.getStakingRewards(alice), 0, "Alice should still have no reward power");
    }

    function testIndependentRewardAndVoteDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice delegates votes to Bob and rewards to Charlie
        vm.prank(alice);
        veToken.delegate(bob);
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Check independent delegation
        assertEq(veToken.delegates(alice), bob, "Alice should delegate votes to Bob");
        assertEq(veToken.rewardDelegates(alice), CHARLIE, "Alice should delegate rewards to Charlie");

        // Check power distribution
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have voting power");
        assertEq(veToken.getVotes(CHARLIE), 0, "Charlie should have no voting power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should have no reward power");
        assertEq(
            veToken.getStakingRewards(CHARLIE),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Charlie should have reward power"
        );
    }

    function testSwitchRewardDelegationIndependently() public {
        // Alice stakes and sets up initial delegations
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Switch only reward delegation to Charlie
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Votes should stay with Bob, rewards move to Charlie
        assertEq(veToken.delegates(alice), bob, "Votes should still be delegated to Bob");
        assertEq(veToken.rewardDelegates(alice), CHARLIE, "Rewards should be delegated to Charlie");
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should keep voting power");
        assertEq(veToken.getStakingRewards(bob), 0, "Bob should lose reward power");
        assertEq(
            veToken.getStakingRewards(CHARLIE),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Charlie should gain reward power"
        );
    }

    function testPoVWRewardCapDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Charlie also stakes (with different amount for clarity)
        vm.prank(CHARLIE);
        veToken.stake(AMOUNT * 2);

        // Check initial PoVW caps
        uint256 aliceCap = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;
        uint256 charlieCap = (AMOUNT * 2) / Constants.POVW_REWARD_CAP_SCALAR;
        assertEq(veToken.getPoVWRewardCap(alice), aliceCap, "Alice should have PoVW cap");
        assertEq(veToken.getPoVWRewardCap(CHARLIE), charlieCap, "Charlie should have PoVW cap");
        assertEq(veToken.getPoVWRewardCap(bob), 0, "Bob should have no PoVW cap initially");

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // PoVW cap should move with reward delegation
        assertEq(veToken.getPoVWRewardCap(alice), 0, "Alice should have no PoVW cap");
        assertEq(veToken.getPoVWRewardCap(bob), aliceCap, "Bob should have Alice's PoVW cap");

        // Charlie also delegates rewards to Bob
        vm.prank(CHARLIE);
        veToken.delegateRewards(bob);

        // Bob should now have the sum of both PoVW caps
        assertEq(veToken.getPoVWRewardCap(alice), 0, "Alice should still have no PoVW cap");
        assertEq(veToken.getPoVWRewardCap(CHARLIE), 0, "Charlie should have no PoVW cap");
        // Rounding error due to integer division by 3
        assertApproxEqAbs(veToken.getPoVWRewardCap(bob), aliceCap + charlieCap, 1, "Bob should have sum of both PoVW caps");
    }

    function testHistoricalRewardPowerAfterDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        uint256 checkpoint1 = vm.getBlockTimestamp();

        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 checkpoint2 = vm.getBlockTimestamp();

        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Alice delegates rewards to Charlie
        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);

        // Check historical reward power
        assertEq(
            veToken.getPastStakingRewards(alice, checkpoint1),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Alice should have had reward power at checkpoint1"
        );
        assertEq(
            veToken.getPastStakingRewards(bob, checkpoint1), 0, "Bob should have had no reward power at checkpoint1"
        );

        assertEq(
            veToken.getPastStakingRewards(alice, checkpoint2), 0, "Alice should have had no reward power at checkpoint2"
        );
        assertEq(
            veToken.getPastStakingRewards(bob, checkpoint2),
            AMOUNT / Constants.REWARD_POWER_SCALAR,
            "Bob should have had reward power at checkpoint2"
        );
        assertEq(
            veToken.getPastStakingRewards(CHARLIE, checkpoint2),
            0,
            "Charlie should have had no reward power at checkpoint2"
        );
    }

    function testHistoricalPoVWCapAfterDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        uint256 checkpoint1 = vm.getBlockTimestamp();
        uint256 expectedCap = AMOUNT / Constants.POVW_REWARD_CAP_SCALAR;

        // Advance time and delegate
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 checkpoint2 = vm.getBlockTimestamp();

        // Advance time to make checkpoint2 a past timestamp
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Check historical PoVW caps
        assertEq(
            veToken.getPastPoVWRewardCap(alice, checkpoint1),
            expectedCap,
            "Alice should have had PoVW cap at checkpoint1"
        );
        assertEq(veToken.getPastPoVWRewardCap(bob, checkpoint1), 0, "Bob should have had no PoVW cap at checkpoint1");

        assertEq(veToken.getPastPoVWRewardCap(alice, checkpoint2), 0, "Alice should have no PoVW cap at checkpoint2");
        assertEq(veToken.getPastPoVWRewardCap(bob, checkpoint2), expectedCap, "Bob should have PoVW cap at checkpoint2");
    }

    function testHistoricalTotalRewardsUnaffectedByDelegation() public {
        // Alice and Bob stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT);

        uint256 totalBefore = veToken.getTotalStakingRewards();

        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Alice delegates rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 totalAfter = veToken.getTotalStakingRewards();

        // Total rewards should remain unchanged
        uint256 expectedTotal = (AMOUNT * 2) / Constants.REWARD_POWER_SCALAR;
        assertEq(totalBefore, expectedTotal, "Total rewards before delegation");
        assertEq(totalAfter, expectedTotal, "Total rewards after delegation");
    }

    // Edge cases and error conditions

    function testCannotDelegateRewardsWithoutPosition() public {
        // Try to delegate rewards without staking
        vm.prank(alice);
        vm.expectRevert(IStaking.NoActivePosition.selector);
        veToken.delegateRewards(bob);
    }

    function testCannotDelegateRewardsWhileWithdrawing() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice initiates unstake
        vm.prank(alice);
        veToken.initiateUnstake();

        // Try to delegate rewards while withdrawing
        vm.prank(alice);
        vm.expectRevert(IRewards.CannotDelegateRewardsWhileWithdrawing.selector);
        veToken.delegateRewards(bob);
    }

    function testCannotInitiateUnstakeWithActiveRewardDelegation() public {
        // Alice stakes and delegates rewards to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Try to initiate unstake with active reward delegation
        vm.prank(alice);
        vm.expectRevert(IStaking.MustUndelegateRewardsFirst.selector);
        veToken.initiateUnstake();

        // Undelegate rewards first
        vm.prank(alice);
        veToken.delegateRewards(alice);

        // Now can initiate unstake
        vm.prank(alice);
        veToken.initiateUnstake();
    }

    function testRewardDelegationToZeroAddress() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Delegate rewards to zero address (should work - represents self-delegation)
        vm.prank(alice);
        veToken.delegateRewards(address(0));

        // Should be same as self-delegation
        assertEq(veToken.rewardDelegates(alice), alice, "Should delegate rewards to self when delegating to zero");
        assertEq(veToken.getStakingRewards(alice), AMOUNT / Constants.REWARD_POWER_SCALAR, "Should have reward power");
    }

    function testRewardDelegationSameAddress() public {
        // Alice stakes and delegates rewards to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 bobRewardsBefore = veToken.getStakingRewards(bob);

        // Delegate rewards to Bob again (should be no-op)
        vm.prank(alice);
        veToken.delegateRewards(bob);

        uint256 bobRewardsAfter = veToken.getStakingRewards(bob);

        assertEq(bobRewardsBefore, bobRewardsAfter, "Rewards should not change when delegating to same address");
        assertEq(veToken.rewardDelegates(alice), bob, "Delegation should remain the same");
    }

    // Events testing

    function testRewardDelegationEvents() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Test reward delegation event - Alice delegates to Bob
        vm.expectEmit(true, true, true, true);
        emit IRewards.RewardDelegateChanged(alice, alice, bob);

        vm.prank(alice);
        veToken.delegateRewards(bob);
    }

    function testNoRewardDelegationEventsWhenSameDelegate() public {
        // Alice stakes (starts with self-delegation)
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Try to delegate rewards to self again - should not emit any events
        vm.recordLogs();
        vm.prank(alice);
        veToken.delegateRewards(alice);
        
        // Check no events were emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0, "No events should be emitted when delegating rewards to same address");

        // Delegate rewards to Bob
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Try to delegate rewards to Bob again - should not emit any events
        vm.recordLogs();
        vm.prank(alice);
        veToken.delegateRewards(bob);
        
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0, "No events should be emitted when delegating rewards to same address");
    }

    function testRewardDelegationEventsMultipleChanges() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // First delegation: Alice -> Bob
        vm.expectEmit(true, true, true, true);
        emit IRewards.RewardDelegateChanged(alice, alice, bob);

        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Second delegation: Alice -> Charlie
        vm.expectEmit(true, true, true, true);
        emit IRewards.RewardDelegateChanged(alice, bob, CHARLIE);

        vm.prank(alice);
        veToken.delegateRewards(CHARLIE);
    }

    function testRewardDelegationEventsBackToSelf() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Delegate rewards to Bob first
        vm.prank(alice);
        veToken.delegateRewards(bob);

        // Delegate rewards back to self
        vm.expectEmit(true, true, true, true);
        emit IRewards.RewardDelegateChanged(alice, bob, alice);

        vm.prank(alice);
        veToken.delegateRewards(alice);
    }

    // Gas optimization tests

    function testGasOptimizationMultipleRewardDelegations() public {
        // Setup multiple stakers
        uint256 numStakers = 10;
        for (uint256 i = 1; i <= numStakers; i++) {
            address staker = address(uint160(i + 100));
            deal(address(zkc), staker, AMOUNT);
            vm.prank(staker);
            zkc.approve(address(veToken), type(uint256).max);
            vm.prank(staker);
            veToken.stake(AMOUNT);
        }

        // Measure gas for reward delegations
        uint256 totalGas = 0;
        for (uint256 i = 1; i <= numStakers; i++) {
            address staker = address(uint160(i + 100));
            uint256 gasBefore = gasleft();
            vm.prank(staker);
            veToken.delegateRewards(CHARLIE);
            uint256 gasUsed = gasBefore - gasleft();
            totalGas += gasUsed;
        }

        uint256 avgGas = totalGas / numStakers;
        console2.log("Average gas per reward delegation:", avgGas);

        // Charlie should have all reward power
        uint256 expectedRewards = (AMOUNT * numStakers) / Constants.REWARD_POWER_SCALAR;
        assertEq(veToken.getStakingRewards(CHARLIE), expectedRewards, "Charlie should have all delegated reward power");
    }

    // ============ Delegation by Signature Tests ============

    function testDelegateRewardsBySig() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Check initial state
        assertEq(veToken.rewardDelegates(aliceSigner), aliceSigner, "Should self-delegate rewards initially");
        assertEq(veToken.getStakingRewards(aliceSigner), AMOUNT / Constants.REWARD_POWER_SCALAR, "Alice should have reward power");

        // Create signature for delegating rewards to Bob
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createRewardDelegationDigest(bobSigner, nonce, expiry);
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Execute reward delegation by signature
        veToken.delegateRewardsBySig(bobSigner, nonce, expiry, v, r, s);

        // Verify delegation
        assertEq(veToken.rewardDelegates(aliceSigner), bobSigner, "Alice should delegate rewards to Bob");
        assertEq(veToken.getStakingRewards(aliceSigner), 0, "Alice should have no reward power");
        assertEq(veToken.getStakingRewards(bobSigner), AMOUNT / Constants.REWARD_POWER_SCALAR, "Bob should have Alice's reward power");
        assertEq(veToken.nonces(aliceSigner), nonce + 1, "Nonce should be incremented");
    }

    function testExpiredRewardDelegationSignature() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Create expired signature
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp - 1; // Already expired
        bytes32 digest = _createRewardDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Should revert
        vm.expectRevert(abi.encodeWithSelector(IRewards.RewardsExpiredSignature.selector, expiry));
        veToken.delegateRewardsBySig(bobSigner, nonce, expiry, v, r, s);
    }

    function testCannotReplayRewardDelegationSignature() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Create and use signature
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createRewardDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // First use should succeed
        veToken.delegateRewardsBySig(bobSigner, nonce, expiry, v, r, s);

        // Try to replay - should fail due to nonce already used
        vm.expectRevert();
        veToken.delegateRewardsBySig(bobSigner, nonce, expiry, v, r, s);
    }

    function testCannotDelegateRewardsBySigWithoutPosition() public {
        // Create signature without staking
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createRewardDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Should revert - no active position
        vm.expectRevert(IStaking.NoActivePosition.selector);
        veToken.delegateRewardsBySig(bobSigner, nonce, expiry, v, r, s);
    }

    function testCannotDelegateRewardsBySigWhileWithdrawing() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Initiate unstake
        vm.prank(aliceSigner);
        veToken.initiateUnstake();

        // Create signature
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createRewardDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Should revert - cannot delegate while withdrawing
        vm.expectRevert(IRewards.CannotDelegateRewardsWhileWithdrawing.selector);
        veToken.delegateRewardsBySig(bobSigner, nonce, expiry, v, r, s);
    }

    function testSharedNonceBetweenDelegations() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // First: delegate votes by signature
        uint256 nonce1 = veToken.nonces(aliceSigner);
        uint256 expiry1 = block.timestamp + 1 hours;
        bytes32 voteStructHash = keccak256(abi.encode(
            keccak256("VoteDelegation(address delegatee,uint256 nonce,uint256 expiry)"),
            bobSigner, nonce1, expiry1
        ));
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("Vote Escrowed ZK Coin")),
                keccak256(bytes("1")),
                block.chainid,
                address(veToken)
            )
        );
        bytes32 finalVoteDigest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, voteStructHash));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ALICE_PK, finalVoteDigest);
        
        veToken.delegateBySig(bobSigner, nonce1, expiry1, v1, r1, s1);
        
        // Verify nonce was incremented
        assertEq(veToken.nonces(aliceSigner), nonce1 + 1, "Nonce should be incremented after vote delegation");

        // Second: delegate rewards by signature (using next nonce)
        uint256 nonce2 = veToken.nonces(aliceSigner);
        uint256 expiry2 = block.timestamp + 1 hours;
        bytes32 rewardDigest = _createRewardDelegationDigest(CHARLIE, nonce2, expiry2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(ALICE_PK, rewardDigest);
        
        veToken.delegateRewardsBySig(CHARLIE, nonce2, expiry2, v2, r2, s2);
        
        // Verify both delegations and nonce
        assertEq(veToken.delegates(aliceSigner), bobSigner, "Votes should be delegated to Bob");
        assertEq(veToken.rewardDelegates(aliceSigner), CHARLIE, "Rewards should be delegated to Charlie");
        assertEq(veToken.nonces(aliceSigner), nonce2 + 1, "Nonce should be incremented again");
    }

    function testCannotUseRewardSignatureForVoteDelegation() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Create a REWARD delegation signature
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createRewardDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Try to use the reward delegation signature for vote delegation
        // This should fail because the signature was created with REWARD_DELEGATION_TYPEHASH
        // but delegateBySig expects VOTE_DELEGATION_TYPEHASH
        vm.expectRevert();
        veToken.delegateBySig(bobSigner, nonce, expiry, v, r, s);

        // Verify nothing changed
        assertEq(veToken.delegates(aliceSigner), aliceSigner, "Votes should still be self-delegated");
        assertEq(veToken.rewardDelegates(aliceSigner), aliceSigner, "Rewards should still be self-delegated");
        assertEq(veToken.nonces(aliceSigner), nonce, "Nonce should not be consumed");
    }
}
