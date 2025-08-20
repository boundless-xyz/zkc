// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {StakingRewards, AlreadyClaimed} from "../src/rewards/StakingRewards.sol";
import {veZKC} from "../src/veZKC.sol";
import {ZKC} from "../src/ZKC.sol";
import {IZKC} from "../src/interfaces/IZKC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StakingRewardsTest is Test {
    ZKC internal zkc;
    veZKC internal vezkc;
    StakingRewards internal rewards;

    address internal admin = address(0xA11CE);
    address internal minter1 = address(0x1001);
    address internal minter2 = address(0x1002);
    address internal user1 = address(0xBEEF1);
    address internal user2 = address(0xBEEF2);

    uint256 internal EPOCH_DURATION;

    function setUp() public {
        vm.startPrank(admin);
        ZKC zkcImpl = new ZKC();
        uint256 supply = zkcImpl.INITIAL_SUPPLY();
        bytes memory zkcInit = abi.encodeCall(ZKC.initialize, (minter1, minter2, supply / 2, supply / 2, admin));
        zkc = ZKC(address(new ERC1967Proxy(address(zkcImpl), zkcInit)));
        zkc.initializeV2();
        EPOCH_DURATION = zkc.EPOCH_DURATION();

        veZKC veImpl = new veZKC();
        bytes memory veInit = abi.encodeCall(veZKC.initialize, (address(zkc), admin));
        vezkc = veZKC(address(new ERC1967Proxy(address(veImpl), veInit)));

        StakingRewards srImpl = new StakingRewards();
        bytes memory srInit = abi.encodeCall(StakingRewards.initialize, (address(zkc), address(vezkc), admin));
        rewards = StakingRewards(address(new ERC1967Proxy(address(srImpl), srInit)));

        zkc.grantRole(zkc.STAKING_MINTER_ROLE(), address(rewards));
        vm.stopPrank();

        deal(address(zkc), user1, 1_000_000e18);
        deal(address(zkc), user2, 1_000_000e18);

        vm.prank(user1);
        zkc.approve(address(vezkc), type(uint256).max);
        vm.prank(user2);
        zkc.approve(address(vezkc), type(uint256).max);
        vm.warp(block.timestamp + 1);
    }

    // Helper functions for staking - updated for withdrawal system
    function _stake(address user, uint256 amount) internal {
        vm.prank(user);
        vezkc.stake(amount); // No lock duration in withdrawal system
    }

    // Helper function to fast-forward epochs
    function _endEpochs(uint256 n) internal {
        vm.warp(block.timestamp + n * EPOCH_DURATION);
    }

    // Internal function to claim rewards for a user and epochs
    function _claimRewards(address user, uint256[] memory epochs) internal returns (uint256) {
        uint256[] memory amounts = rewards.calculateRewards(user, epochs);
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        if (totalAmount > 0) {
            vm.expectEmit(true, true, true, true);
            emit IZKC.StakingRewardsClaimed(user, totalAmount);
        }
        vm.prank(user);
        uint256 amount = rewards.claimRewards(epochs);
        return amount;
    }

    // Helper function to claim rewards for a user in a single epoch
    function _claimRewardsForEpoch(address user, uint256 epoch) internal returns (uint256) {
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = epoch;
        return _claimRewards(user, epochs);
    }

    // Test single user gets full emission
    function testSingleUserGetsFullEmission() public {
        _stake(user1, 100e18);
        _endEpochs(1);
        uint256 claimed = _claimRewardsForEpoch(user1, 0);
        assertEq(claimed, zkc.getStakingEmissionsForEpoch(0));
    }

    // Test two users split pro-rata
    function testTwoUsersSplitProRata() public {
        _stake(user1, 100e18);
        _stake(user2, 300e18);
        _endEpochs(1);
        uint256 c1 = _claimRewardsForEpoch(user1, 0);
        uint256 c2 = _claimRewardsForEpoch(user2, 0);
        uint256 total = zkc.getStakingEmissionsForEpoch(0);
        assertEq(c1 + c2, total);
        assertApproxEqRel(c1, total * 100 / 400, 1e16);
        assertApproxEqRel(c2, total * 300 / 400, 1e16);
    }

    // Test cannot claim rewards for future epoch
    function testCannotClaimFutureEpoch() public {
        _stake(user1, 50e18);
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(IZKC.EpochNotEnded.selector, 0));
        vm.prank(user1);
        rewards.claimRewards(epochs);
    }

    // Test cannot claim rewards for an epoch that has already been claimed
    function testCannotDoubleClaim() public {
        _stake(user1, 50e18);
        _endEpochs(1);
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 0;
        vm.prank(user1);
        rewards.claimRewards(epochs);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AlreadyClaimed.selector, 0));
        rewards.claimRewards(epochs);
    }

    // Test batch claim for multiple epochs
    function testBatchClaim() public {
        _stake(user1, 50e18);
        _endEpochs(3);
        uint256[] memory epochs = new uint256[](3);
        epochs[0] = 0;
        epochs[1] = 1;
        epochs[2] = 2;
        uint256 totalClaim = _claimRewards(user1, epochs);
        uint256 expected;
        expected += zkc.getStakingEmissionsForEpoch(0);
        expected += zkc.getStakingEmissionsForEpoch(1);
        expected += zkc.getStakingEmissionsForEpoch(2);
        assertEq(totalClaim, expected);
    }

    // Delegation should not transfer reward power to delegatee.
    // function testDelegationDoesNotAffectRewards() public {
    //     _stake(user1, 100e18);
    //     _stake(user2, 300e18);
    //     // Delegate voting power from user1 to user2
    //     vm.prank(user1);
    //     vezkc.delegate(user2);
    //     _endEpochs(1);
    //     uint256 emission = zkc.getStakingEmissionsForEpoch(0);
    //     uint256 c1 = _claimRewardsForEpoch(user1, 0);
    //     uint256 c2 = _claimRewardsForEpoch(user2, 0);
    //     assertEq(c1 + c2, emission, "Total emission mismatch");
    //     uint256 exp1 = (emission * 100) / 400; // 1/4
    //     uint256 exp2 = emission - exp1; // 3/4
    //     assertApproxEqRel(c1, exp1, 1e16, "Delegation changed delegator rewards");
    //     assertApproxEqRel(c2, exp2, 1e16, "Delegatee improperly gained reward power");
    //     // checking voting power
    //     uint256 user1VotingPower = vezkc.getVotes(user1);
    //     uint256 user2VotingPower = vezkc.getVotes(user2);
    //     assertEq(user1VotingPower, 0, "User1 should have no voting power");
    //     assertEq(user2VotingPower, 400, "User2 should have full voting power");
    // }

    // Claiming an epoch with no stake should mint nothing, mark claimed, and block later claims.
    function testClaimZeroNoStake() public {
        _endEpochs(1); // finish epoch 0 with no stakers
        uint256 balBefore = zkc.balanceOf(user1);
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 0;
        vm.prank(user1);
        uint256 claimed = rewards.claimRewards(epochs);
        assertEq(claimed, 0);
        assertEq(zkc.balanceOf(user1), balBefore, "Balance changed despite zero claim");
        // Second attempt reverts because marked claimed even if zero
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AlreadyClaimed.selector, 0));
        rewards.claimRewards(epochs);
    }

    // Mixed past + future epochs in one batch should revert on the future epoch.
    function testCannotClaimBatchContainingFutureEpoch() public {
        _stake(user1, 100e18);
        _endEpochs(2); // epochs 0 and 1 finished; currentEpoch == 2
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = 0;
        epochs[1] = 2; // future
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IZKC.EpochNotEnded.selector, 2));
        rewards.claimRewards(epochs);
    }

    // Duplicate epoch in the same batch should revert on second encounter.
    function testDuplicateEpochInSameBatchReverts() public {
        _stake(user1, 50e18);
        _endEpochs(1);
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = 0;
        epochs[1] = 0; // duplicate
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AlreadyClaimed.selector, 0));
        rewards.claimRewards(epochs);
    }

    // Calling calculateRewards must not mark epochs as claimed.
    function testCalculateDoesNotAffectClaimStatus() public {
        _stake(user1, 80e18);
        _endEpochs(1);
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 0;
        rewards.calculateRewards(user1, epochs); // should not affect
        assertFalse(rewards.hasUserClaimedRewards(user1, 0));
        vm.prank(user1);
        rewards.claimRewards(epochs); // should succeed
    }

    // User staking after an epoch ends cannot retroactively earn that epoch; claim marks it and blocks later retroactive attempts.
    function testNoRetroactiveEarningForPastEpoch() public {
        _endEpochs(1); // epoch 0 ends with no stake
        _stake(user1, 100e18); // stake in epoch 1
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 0; // past epoch with zero power
        vm.prank(user1);
        uint256 claimed = rewards.claimRewards(epochs);
        assertEq(claimed, 0);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AlreadyClaimed.selector, 0));
        rewards.claimRewards(epochs);
    }

    // Unsorted epoch list should still succeed and sum emissions correctly.
    function testUnsortedEpochBatchClaim() public {
        _stake(user1, 120e18);
        _endEpochs(3); // epochs 0,1,2
        uint256[] memory epochs = new uint256[](3);
        epochs[0] = 2;
        epochs[1] = 0;
        epochs[2] = 1;
        uint256 expected =
            zkc.getStakingEmissionsForEpoch(0) + zkc.getStakingEmissionsForEpoch(1) + zkc.getStakingEmissionsForEpoch(2);
        uint256[] memory calc = rewards.calculateRewards(user1, epochs);
        uint256 sum;
        for (uint256 i; i < calc.length; ++i) {
            sum += calc[i];
        }
        vm.prank(user1);
        uint256 claimed = rewards.claimRewards(epochs);
        assertEq(claimed, sum, "Claimed != calculated sum");
        assertEq(claimed, expected, "Claimed != expected emissions (single staker)");
    }

    // Test reward power drops to zero when withdrawing (new test for withdrawal system)
    function testWithdrawingUserGetsNoRewards() public {
        _stake(user1, 100e18);
        _stake(user2, 100e18);

        // User1 initiates withdrawal
        vm.prank(user1);
        vezkc.initiateUnstake();

        _endEpochs(1); // epoch ends while user1 is withdrawing

        // User1 should get no rewards due to withdrawal, user2 gets all
        uint256 c1 = _claimRewardsForEpoch(user1, 0);
        uint256 c2 = _claimRewardsForEpoch(user2, 0);
        uint256 total = zkc.getStakingEmissionsForEpoch(0);

        assertEq(c1, 0, "Withdrawing user should get no rewards");
        assertEq(c2, total, "Non-withdrawing user should get all rewards");
    }

    // Test rewards distribution when user completes withdrawal mid-epoch
    function testRewardsWithMidEpochWithdrawal() public {
        _stake(user1, 100e18);
        _stake(user2, 100e18);

        // Start epoch 0, users split rewards
        _endEpochs(1);
        uint256 c1_epoch0 = _claimRewardsForEpoch(user1, 0);
        uint256 c2_epoch0 = _claimRewardsForEpoch(user2, 0);
        uint256 total_epoch0 = zkc.getStakingEmissionsForEpoch(0);

        // Both users should get equal rewards for epoch 0
        assertApproxEqRel(c1_epoch0, total_epoch0 / 2, 1e16);
        assertApproxEqRel(c2_epoch0, total_epoch0 / 2, 1e16);

        // User1 initiates withdrawal during epoch 1
        vm.prank(user1);
        vezkc.initiateUnstake();

        _endEpochs(1); // finish epoch 1

        // For epoch 1, user1 gets no rewards (withdrawing), user2 gets all
        uint256 c1_epoch1 = _claimRewardsForEpoch(user1, 1);
        uint256 c2_epoch1 = _claimRewardsForEpoch(user2, 1);
        uint256 total_epoch1 = zkc.getStakingEmissionsForEpoch(1);

        assertEq(c1_epoch1, 0, "Withdrawing user should get no rewards for epoch 1");
        assertEq(c2_epoch1, total_epoch1, "Non-withdrawing user should get all rewards for epoch 1");
    }

    // Gas Benchmarks
    function _runBatchGas(uint256 epochsToSimulate, uint256 stakeAmount, string memory label) internal {
        _stake(user1, stakeAmount);
        _endEpochs(epochsToSimulate);
        uint256[] memory epochs = new uint256[](epochsToSimulate);
        for (uint256 i; i < epochsToSimulate; ++i) {
            epochs[i] = i;
        }
        vm.prank(user1);
        uint256 total = rewards.claimRewards(epochs);
        vm.snapshotGasLastCall(label);
        assertGt(total, 0);
    }

    function testGas_SingleClaim() public {
        _runBatchGas(1, 100e18, "claimRewards: single epoch claim");
    }

    function testGas_BatchClaim15Epochs() public {
        _runBatchGas(15, 150e18, "claimRewards: batch claim 15 epochs");
    }

    function testGas_BatchClaim30Epochs() public {
        _runBatchGas(30, 300e18, "claimRewards: batch claim 30 epochs");
    }

    function testGas_CalculateRewards() public {
        _stake(user1, 100e18);
        _endEpochs(5);
        uint256[] memory epochs = new uint256[](5);
        for (uint256 i; i < 5; ++i) {
            epochs[i] = i;
        }
        uint256[] memory amounts = rewards.calculateRewards(user1, epochs);
        vm.snapshotGasLastCall("calculateRewards: calculate 5 epochs");
        assertGt(amounts[0], 0);
    }
}
