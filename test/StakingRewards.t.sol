// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {
    StakingRewards, StakingRewardClaimed, AlreadyClaimed, EpochNotFinished
} from "../src/rewards/StakingRewards.sol";
import {veZKC} from "../src/veZKC.sol";
import {ZKC} from "../src/ZKC.sol";
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

    uint256 constant EPOCH_DURATION = 2 days;

    function setUp() public {
        vm.startPrank(admin);
        ZKC zkcImpl = new ZKC();
        uint256 supply = zkcImpl.INITIAL_SUPPLY();
        bytes memory zkcInit = abi.encodeCall(ZKC.initialize, (minter1, minter2, supply / 2, supply / 2, admin));
        zkc = ZKC(address(new ERC1967Proxy(address(zkcImpl), zkcInit)));
        zkc.initializeV2();

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

    function _stake(address user, uint256 amount) internal {
        vm.prank(user);
        vezkc.stake(amount, type(uint256).max); // max lock
    }

    function _endEpochs(uint256 n) internal {
        vm.warp(block.timestamp + n * EPOCH_DURATION);
    }

    function _claimRewards(address user, uint256[] memory epochs) internal returns (uint256) {
        uint256[] memory amounts = rewards.calculateRewards(user, epochs);
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        vm.expectEmit(true, true, true, true);
        emit StakingRewardClaimed(user, epochs, totalAmount);
        vm.prank(user);
        uint256 amount = rewards.claimRewards(epochs);
        return amount;
    }

    function _claimRewardsForEpoch(address user, uint256 epoch) internal returns (uint256) {
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = epoch;
        return _claimRewards(user, epochs);
    }

    function testSingleUserGetsFullEmission() public {
        _stake(user1, 100e18);
        _endEpochs(1);
        uint256 claimed = _claimRewardsForEpoch(user1, 0);
        assertEq(claimed, zkc.getStakingEmissionsForEpoch(0));
    }

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

    function testCannotClaimFutureEpoch() public {
        _stake(user1, 50e18);
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(EpochNotFinished.selector, 0));
        vm.prank(user1);
        rewards.claimRewards(epochs);
    }

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
        _runBatchGas(1, 100e18, "stake claim: single");
    }

    function testGas_BatchClaim15Epochs() public {
        _runBatchGas(15, 150e18, "stake claim: batch15");
    }

    function testGas_BatchClaim30Epochs() public {
        _runBatchGas(30, 300e18, "stake claim: batch30");
    }

    // Delegation should not transfer reward power to delegatee.
    function testDelegationDoesNotAffectRewards() public {
        _stake(user1, 100e18);
        _stake(user2, 300e18);
        // Delegate voting power from user1 to user2
        vm.prank(user1);
        vezkc.delegate(user2);
        _endEpochs(1);
        uint256 emission = zkc.getStakingEmissionsForEpoch(0);
        uint256 c1 = _claimRewardsForEpoch(user1, 0);
        uint256 c2 = _claimRewardsForEpoch(user2, 0);
        assertEq(c1 + c2, emission, "Total emission mismatch");
        uint256 exp1 = (emission * 100) / 400;
        uint256 exp2 = emission - exp1; // remainder
        assertApproxEqRel(c1, exp1, 1e16, "Delegation changed delegator rewards");
        assertApproxEqRel(c2, exp2, 1e16, "Delegatee improperly gained reward power");
    }
}
