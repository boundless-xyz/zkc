// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../veZKC.t.sol";
import "../../src/interfaces/IVotes.sol";
import "../../src/interfaces/IStaking.sol";
import {IVotes as OZIVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {console2} from "forge-std/Test.sol";

contract VotesDelegationTest is veZKCTest {
    using MessageHashUtils for bytes32;

    address public constant CHARLIE = address(3);
    address public constant DAVE = address(4);

    // Test accounts with known private keys for signature tests
    uint256 constant ALICE_PK = 0xA11CE;
    uint256 constant BOB_PK = 0xB0B;
    address aliceSigner;
    address bobSigner;

    // EIP-712 constants
    bytes32 private constant VOTE_DELEGATION_TYPEHASH =
        keccak256("VoteDelegation(address delegatee,uint256 nonce,uint256 expiry)");
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

    // Helper function to create EIP-712 digest for vote delegation
    function _createVoteDelegationDigest(address delegatee, uint256 nonce, uint256 expiry)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(VOTE_DELEGATION_TYPEHASH, delegatee, nonce, expiry));
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

    // Basic delegation tests
    function testSelfDelegationByDefault() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Check Alice delegates to herself by default
        assertEq(veToken.delegates(alice), alice, "Should self-delegate by default");
        assertEq(veToken.getVotes(alice), AMOUNT, "Should have voting power equal to stake");
    }

    function testSimpleDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        vm.snapshotGasLastCall("delegate_votes_initial");

        // Check delegation
        assertEq(veToken.delegates(alice), bob, "Alice should delegate to Bob");
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power");
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have Alice's voting power");
    }

    function testDelegationChangeUpdatesVotes() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have Alice's voting power");

        // Alice re-delegates to Charlie
        vm.prank(alice);
        veToken.delegate(CHARLIE);
        vm.snapshotGasLastCall("delegate_votes_redelegation");

        assertEq(veToken.delegates(alice), CHARLIE, "Alice should delegate to Charlie");
        assertEq(veToken.getVotes(bob), 0, "Bob should have no voting power");
        assertEq(veToken.getVotes(CHARLIE), AMOUNT, "Charlie should have Alice's voting power");
    }

    function testMultipleDelegators() public {
        // Alice and Bob stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT * 2);

        // Both delegate to Charlie
        vm.prank(alice);
        veToken.delegate(CHARLIE);
        vm.prank(bob);
        veToken.delegate(CHARLIE);

        // Charlie should have combined voting power
        assertEq(veToken.getVotes(CHARLIE), AMOUNT * 3, "Charlie should have combined voting power");
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power");
        assertEq(veToken.getVotes(bob), 0, "Bob should have no voting power");
    }

    function testDelegateBackToSelf() public {
        // Alice stakes and delegates to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);

        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have Alice's voting power");

        // Alice delegates back to herself
        vm.prank(alice);
        veToken.delegate(alice);

        assertEq(veToken.delegates(alice), alice, "Alice should delegate to herself");
        assertEq(veToken.getVotes(alice), AMOUNT, "Alice should have her voting power back");
        assertEq(veToken.getVotes(bob), 0, "Bob should have no voting power");
    }

    function testAddToStakeWithDelegation() public {
        // Alice stakes and delegates to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);

        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should have initial voting power");

        // Alice adds to her stake
        vm.prank(alice);
        veToken.addToStake(AMOUNT);

        // Bob's voting power should increase
        assertEq(veToken.getVotes(bob), AMOUNT * 2, "Bob should have increased voting power");
        assertEq(veToken.getVotes(alice), 0, "Alice should still have no voting power");
    }

    // Delegation with chain tests

    function testDelegationChain() public {
        // Alice, Bob, and Charlie stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT);
        vm.prank(CHARLIE);
        veToken.stake(AMOUNT);

        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);

        // Bob has his own + Alice's power
        assertEq(veToken.getVotes(bob), AMOUNT * 2, "Bob should have combined power");

        // Bob delegates to Charlie (Bob's own stake moves, Alice's delegation stays with Bob)
        vm.prank(bob);
        veToken.delegate(CHARLIE);

        // Check final distribution
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power");
        assertEq(veToken.getVotes(bob), AMOUNT, "Bob should only have Alice's delegated power");
        assertEq(veToken.getVotes(CHARLIE), AMOUNT * 2, "Charlie should have his own + Bob's stake");
    }

    function testDelegationIsNonTransitive() public {
        // Setup: Three users with different stake amounts
        uint256 aliceStake = 1000 ether;
        uint256 bobStake = 500 ether;
        uint256 charlieStake = 200 ether;
        // All three users stake
        vm.prank(alice);
        veToken.stake(aliceStake);
        vm.prank(bob);
        veToken.stake(bobStake);
        vm.prank(CHARLIE);
        veToken.stake(charlieStake);
        // Initial state - everyone self-delegates
        assertEq(veToken.getVotes(alice), aliceStake, "Alice should have her own voting power");
        assertEq(veToken.getVotes(bob), bobStake, "Bob should have his own voting power");
        assertEq(veToken.getVotes(CHARLIE), charlieStake, "Charlie should have his own voting power");

        // Alice delegates her voting power to Bob
        vm.prank(alice);
        veToken.delegate(bob);

        // Bob now has his own stake + Alice's delegated stake
        assertEq(veToken.getVotes(alice), 0, "Alice should have no voting power after delegating");
        assertEq(veToken.getVotes(bob), bobStake + aliceStake, "Bob should have his own + Alice's voting power");
        assertEq(veToken.getVotes(CHARLIE), charlieStake, "Charlie's voting power unchanged");
        // Bob delegates his voting power to Charlie
        // IMPORTANT: Only Bob's own stake moves to Charlie, Alice's delegation stays with Bob
        vm.prank(bob);
        veToken.delegate(CHARLIE);
        // Final distribution demonstrates non-transitivity:
        // - Alice's delegation stays with Bob (doesn't transfer to Charlie)
        // - Only Bob's own stake goes to Charlie
        assertEq(veToken.getVotes(alice), 0, "Alice still has no voting power");
        assertEq(veToken.getVotes(bob), aliceStake, "Bob retains Alice's delegated power");
        assertEq(veToken.getVotes(CHARLIE), charlieStake + bobStake, "Charlie has his own + Bob's stake only");
        // Verify the total is conserved
        uint256 totalVotes = veToken.getVotes(alice) + veToken.getVotes(bob) + veToken.getVotes(CHARLIE);
        assertEq(totalVotes, aliceStake + bobStake + charlieStake, "Total voting power is conserved");
    }

    // Historical delegation tests

    function testHistoricalVotingPowerAfterDelegation() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        uint256 checkpoint1 = vm.getBlockTimestamp();

        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);

        uint256 checkpoint2 = vm.getBlockTimestamp();

        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        // Alice delegates to Charlie
        vm.prank(alice);
        veToken.delegate(CHARLIE);

        // Check historical voting power
        assertEq(veToken.getPastVotes(alice, checkpoint1), AMOUNT, "Alice should have had voting power at checkpoint1");
        assertEq(veToken.getPastVotes(bob, checkpoint1), 0, "Bob should have had no voting power at checkpoint1");

        assertEq(veToken.getPastVotes(alice, checkpoint2), 0, "Alice should have had no voting power at checkpoint2");
        assertEq(veToken.getPastVotes(bob, checkpoint2), AMOUNT, "Bob should have had voting power at checkpoint2");
        assertEq(
            veToken.getPastVotes(CHARLIE, checkpoint2), 0, "Charlie should have had no voting power at checkpoint2"
        );
    }

    function testHistoricalTotalSupplyUnaffectedByDelegation() public {
        // Alice and Bob stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT);

        uint256 checkpoint1 = vm.getBlockTimestamp();

        // Advance time
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        uint256 totalBefore = veToken.getPastTotalSupply(checkpoint1);

        // Alice delegates to Bob
        vm.prank(alice);
        veToken.delegate(bob);

        uint256 checkpoint2 = vm.getBlockTimestamp();

        // Advance time again to make checkpoint2 a past timestamp
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        uint256 totalAfter = veToken.getPastTotalSupply(checkpoint2);

        // Total supply should remain unchanged
        assertEq(totalBefore, AMOUNT * 2, "Total supply before delegation");
        assertEq(totalAfter, AMOUNT * 2, "Total supply after delegation");
    }

    // Edge cases and error conditions

    function testCannotDelegateWithoutPosition() public {
        // Try to delegate without staking
        vm.prank(alice);
        vm.expectRevert(IStaking.NoActivePosition.selector);
        veToken.delegate(bob);
    }

    function testCannotDelegateWhileWithdrawing() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Alice initiates unstake
        vm.prank(alice);
        veToken.initiateUnstake();

        // Try to delegate while withdrawing
        vm.prank(alice);
        vm.expectRevert(IVotes.CannotDelegateVotesWhileWithdrawing.selector);
        veToken.delegate(bob);
    }

    function testCannotInitiateUnstakeWithActiveDelegation() public {
        // Alice stakes and delegates to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);

        // Try to initiate unstake with active delegation
        vm.prank(alice);
        vm.expectRevert(IStaking.MustUndelegateVotesFirst.selector);
        veToken.initiateUnstake();

        // Undelegate first
        vm.prank(alice);
        veToken.delegate(alice);

        // Now can initiate unstake
        vm.prank(alice);
        veToken.initiateUnstake();
    }

    function testDelegationToZeroAddress() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Delegate to zero address (should work - represents self-delegation)
        vm.prank(alice);
        veToken.delegate(address(0));

        // Should be same as self-delegation
        assertEq(veToken.delegates(alice), alice, "Should delegate to self when delegating to zero");
        assertEq(veToken.getVotes(alice), AMOUNT, "Should have voting power");
    }

    function testDelegationSameAddress() public {
        // Alice stakes and delegates to Bob
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(alice);
        veToken.delegate(bob);

        uint256 bobVotesBefore = veToken.getVotes(bob);

        // Delegate to Bob again (should be no-op)
        vm.prank(alice);
        veToken.delegate(bob);

        uint256 bobVotesAfter = veToken.getVotes(bob);

        assertEq(bobVotesBefore, bobVotesAfter, "Votes should not change when delegating to same address");
        assertEq(veToken.delegates(alice), bob, "Delegation should remain the same");
    }

    function testDelegationEvents() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Test delegation event - Alice delegates to Bob
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateChanged(alice, alice, bob);

        // Alice loses voting power
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(alice, AMOUNT, 0);

        // Bob gains voting power
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(bob, 0, AMOUNT);

        vm.prank(alice);
        veToken.delegate(bob);
    }

    function testDelegationEventsMultipleChanges() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // First delegation: Alice -> Bob
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateChanged(alice, alice, bob);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(alice, AMOUNT, 0);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(bob, 0, AMOUNT);

        vm.prank(alice);
        veToken.delegate(bob);

        // Second delegation: Alice -> Charlie
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateChanged(alice, bob, CHARLIE);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(bob, AMOUNT, 0);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(CHARLIE, 0, AMOUNT);

        vm.prank(alice);
        veToken.delegate(CHARLIE);
    }

    function testDelegationEventsBackToSelf() public {
        // Alice stakes
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Delegate to Bob first
        vm.prank(alice);
        veToken.delegate(bob);

        // Delegate back to self
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateChanged(alice, bob, alice);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(bob, AMOUNT, 0);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(alice, 0, AMOUNT);

        vm.prank(alice);
        veToken.delegate(alice);
    }

    function testNoDelegationEventsWhenSameDelegate() public {
        // Alice stakes (starts with self-delegation)
        vm.prank(alice);
        veToken.stake(AMOUNT);

        // Try to delegate to self again - should not emit any events
        vm.recordLogs();
        vm.prank(alice);
        veToken.delegate(alice);

        // Check no events were emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0, "No events should be emitted when delegating to same address");

        // Delegate to Bob
        vm.prank(alice);
        veToken.delegate(bob);

        // Try to delegate to Bob again - should not emit any events
        vm.recordLogs();
        vm.prank(alice);
        veToken.delegate(bob);

        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0, "No events should be emitted when delegating to same address");
    }

    function testDelegationEventsWithMultipleDelegators() public {
        // Alice and Bob both stake
        vm.prank(alice);
        veToken.stake(AMOUNT);
        vm.prank(bob);
        veToken.stake(AMOUNT * 2);

        // Alice delegates to Charlie
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateChanged(alice, alice, CHARLIE);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(alice, AMOUNT, 0);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(CHARLIE, 0, AMOUNT);

        vm.prank(alice);
        veToken.delegate(CHARLIE);

        // Bob also delegates to Charlie
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateChanged(bob, bob, CHARLIE);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(bob, AMOUNT * 2, 0);
        vm.expectEmit(true, true, true, true);
        emit OZIVotes.DelegateVotesChanged(CHARLIE, AMOUNT, AMOUNT * 3);

        vm.prank(bob);
        veToken.delegate(CHARLIE);
    }

    // ============ Delegation by Signature Tests ============

    function testDelegateVotesBySig() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Check initial state
        assertEq(veToken.delegates(aliceSigner), aliceSigner, "Should self-delegate initially");
        assertEq(veToken.getVotes(aliceSigner), AMOUNT, "Alice should have voting power");

        // Create signature for delegating to Bob
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createVoteDelegationDigest(bobSigner, nonce, expiry);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Execute delegation by signature
        veToken.delegateBySig(bobSigner, nonce, expiry, v, r, s);

        // Verify delegation
        assertEq(veToken.delegates(aliceSigner), bobSigner, "Alice should delegate to Bob");
        assertEq(veToken.getVotes(aliceSigner), 0, "Alice should have no voting power");
        assertEq(veToken.getVotes(bobSigner), AMOUNT, "Bob should have Alice's voting power");
        assertEq(veToken.nonces(aliceSigner), nonce + 1, "Nonce should be incremented");
    }

    function testExpiredVoteDelegationSignature() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Create expired signature
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp - 1; // Already expired
        bytes32 digest = _createVoteDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Should revert
        vm.expectRevert(abi.encodeWithSelector(OZIVotes.VotesExpiredSignature.selector, expiry));
        veToken.delegateBySig(bobSigner, nonce, expiry, v, r, s);
    }

    function testInvalidNonceVoteDelegation() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Create signature with wrong nonce
        uint256 wrongNonce = veToken.nonces(aliceSigner) + 1; // Wrong nonce
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createVoteDelegationDigest(bobSigner, wrongNonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Should revert with invalid nonce error
        vm.expectRevert();
        veToken.delegateBySig(bobSigner, wrongNonce, expiry, v, r, s);
    }

    function testCannotReplayVoteDelegationSignature() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Create and use signature
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createVoteDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // First use should succeed
        veToken.delegateBySig(bobSigner, nonce, expiry, v, r, s);

        // Try to replay - should fail due to nonce already used
        vm.expectRevert();
        veToken.delegateBySig(bobSigner, nonce, expiry, v, r, s);
    }

    function testCannotDelegateVotesBySigWithoutPosition() public {
        // Create signature without staking
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createVoteDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Should revert - no active position
        vm.expectRevert(IStaking.NoActivePosition.selector);
        veToken.delegateBySig(bobSigner, nonce, expiry, v, r, s);
    }

    function testCannotDelegateVotesBySigWhileWithdrawing() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Initiate unstake
        vm.prank(aliceSigner);
        veToken.initiateUnstake();

        // Create signature
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createVoteDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Should revert - cannot delegate while withdrawing
        vm.expectRevert(IVotes.CannotDelegateVotesWhileWithdrawing.selector);
        veToken.delegateBySig(bobSigner, nonce, expiry, v, r, s);
    }

    function testMultipleSignersDelegateVotesToSameAccount() public {
        // Both Alice and Bob stake
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);
        vm.prank(bobSigner);
        veToken.stake(AMOUNT * 2);

        // Alice delegates votes to Charlie by signature
        uint256 aliceNonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 aliceDigest = _createVoteDelegationDigest(CHARLIE, aliceNonce, expiry);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ALICE_PK, aliceDigest);

        veToken.delegateBySig(CHARLIE, aliceNonce, expiry, v1, r1, s1);

        // Bob also delegates votes to Charlie by signature
        uint256 bobNonce = veToken.nonces(bobSigner);
        bytes32 bobDigest = _createVoteDelegationDigest(CHARLIE, bobNonce, expiry);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(BOB_PK, bobDigest);

        veToken.delegateBySig(CHARLIE, bobNonce, expiry, v2, r2, s2);

        // Verify Charlie has combined voting power
        assertEq(veToken.getVotes(CHARLIE), AMOUNT * 3, "Charlie should have combined voting power");
    }

    function testCannotUseVoteSignatureForRewardDelegation() public {
        // Alice stakes
        vm.prank(aliceSigner);
        veToken.stake(AMOUNT);

        // Create a VOTE delegation signature
        uint256 nonce = veToken.nonces(aliceSigner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _createVoteDelegationDigest(bobSigner, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Try to use the vote delegation signature for reward delegation
        // This should fail because the signature was created with VOTE_DELEGATION_TYPEHASH
        // but delegateRewardsBySig expects REWARD_DELEGATION_TYPEHASH
        vm.expectRevert();
        veToken.delegateRewardsBySig(bobSigner, nonce, expiry, v, r, s);

        // Verify nothing changed
        assertEq(veToken.rewardDelegates(aliceSigner), aliceSigner, "Rewards should still be self-delegated");
        assertEq(veToken.delegates(aliceSigner), aliceSigner, "Votes should still be self-delegated");
        assertEq(veToken.nonces(aliceSigner), nonce, "Nonce should not be consumed");
    }
}
