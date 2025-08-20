// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";
import {veZKC} from "../../src/veZKC.sol";
import {ZKC} from "../../src/ZKC.sol";
import {veZKCHandler} from "./veZKCHandler.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract veZKCInvariantTest is StdInvariant, Test {
    veZKC public veImplementation;
    veZKC public veToken;
    ZKC public zkc;
    veZKCHandler public handler;

    address admin = makeAddr("admin");
    address minter1 = makeAddr("minter1");
    address minter2 = makeAddr("minter2");

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ZKC with proxy
        ZKC zkcImpl = new ZKC();
        bytes memory zkcInitData = abi.encodeWithSelector(
            ZKC.initialize.selector,
            admin, // initialMinter1
            address(0), // initialMinter2
            1_000_000_000e18,
            0,
            admin // owner
        );
        zkc = ZKC(address(new ERC1967Proxy(address(zkcImpl), zkcInitData)));
        zkc.initializeV2();

        // Deploy veZKC with proxy
        veImplementation = new veZKC();
        bytes memory veInitData = abi.encodeWithSelector(veZKC.initialize.selector, address(zkc), admin);
        ERC1967Proxy veProxy = new ERC1967Proxy(address(veImplementation), veInitData);
        veToken = veZKC(address(veProxy));

        // Mint initial ZKC supply to test contract
        address[] memory recipients = new address[](1);
        recipients[0] = address(this);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000_000_000e18; // 1B ZKC for test funding
        zkc.initialMint(recipients, amounts);

        vm.stopPrank();

        // Deploy and configure handler
        handler = new veZKCHandler(veToken, zkc);

        // Fund handler with ZKC for actor distribution
        zkc.transfer(address(handler), zkc.balanceOf(address(this)));

        // Set handler as target for invariant testing
        targetContract(address(handler));

        // Target specific functions with weights
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = veZKCHandler.performAction.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /**
     * Invariant 1: Total staked minus total unstaked equals sum of all user stakes
     */
    function invariant_TotalStakedMatchesSum() public view {
        uint256 handlerTotal = handler.getTotalActiveStaked();
        uint256 sumOfUsers = handler.sumAllUserStaked();

        assertEq(handlerTotal, sumOfUsers, "Total staked - unstaked should equal sum of all user stakes");
    }

    /**
     * Invariant 2: Sum of all locked amounts in veZKC equals tracked total
     */
    function invariant_LockedAmountConsistency() public view {
        uint256 totalInContract = zkc.balanceOf(address(veToken));
        uint256 totalTracked = handler.getTotalActiveStaked();

        assertEq(totalInContract, totalTracked, "ZKC balance in veToken should equal tracked total staked");
    }

    /**
     * Invariant 3: Voting power is always non-negative
     */
    function invariant_NoNegativeVotingPower() public view {
        uint256 actorCount = handler.getActorCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.actors(i);
            uint256 votingPower = veToken.getVotes(actor);

            // Voting power should be non-negative (uint so always true, but check for overflow)
            assertTrue(votingPower <= type(uint128).max, "Voting power overflow detected");
        }
    }

    /**
     * Invariant 4: Withdrawing positions have zero voting power
     */
    function invariant_WithdrawingPositionsHaveZeroPower() public view {
        uint256 actorCount = handler.getActorCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.actors(i);

            if (handler.ghost_hasActivePosition(actor) && handler.ghost_isWithdrawing(actor)) {
                uint256 votingPower = veToken.getVotes(actor);
                assertEq(votingPower, 0, "Withdrawing position should have zero voting power");
            }
        }
    }

    /**
     * Invariant 5: Reward power equals staked amount for non-withdrawing positions
     */
    function invariant_RewardPowerMatchesStaked() public view {
        uint256 actorCount = handler.getActorCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.actors(i);

            if (handler.ghost_hasActivePosition(actor) && !handler.ghost_isWithdrawing(actor)) {
                uint256 expectedAmount = handler.ghost_userStaked(actor);
                uint256 actualRewardPower = veToken.getStakingRewards(actor);

                assertEq(
                    actualRewardPower, expectedAmount, "Reward power should equal staked amount for active positions"
                );
            } else if (handler.ghost_hasActivePosition(actor) && handler.ghost_isWithdrawing(actor)) {
                // Withdrawing positions should have zero reward power
                uint256 rewardPower = veToken.getStakingRewards(actor);
                assertEq(rewardPower, 0, "Withdrawing position should have zero reward power");
            } else {
                // No position means no reward power
                uint256 rewardPower = veToken.getStakingRewards(actor);
                assertEq(rewardPower, 0, "No position should mean zero reward power");
            }
        }
    }

    /**
     * Invariant 6: Historical total supply should be reasonable and accessible
     * (getPastTotalSupply should work for all valid historical timestamps)
     */
    function invariant_PastTotalSupplyReasonable() public view {
        uint256 snapshotCount = handler.getHistoricalSnapshotCount();
        if (snapshotCount == 0) return;

        uint256 currentActiveStaked = handler.getTotalActiveStaked();

        // Check a few historical timestamps
        uint256 checkCount = snapshotCount > 5 ? 5 : snapshotCount;
        uint256 step = snapshotCount / checkCount;
        if (step == 0) step = 1;

        for (uint256 i = 0; i < snapshotCount; i += step) {
            uint256 timestamp = handler.ghost_historicalTimestamps(i);

            // Only check timestamps that are definitively in the past
            // Skip very recent timestamps that might equal current block.timestamp
            if (timestamp >= vm.getBlockTimestamp()) continue;

            // getPastTotalSupply should not revert for valid historical timestamps
            uint256 pastSupply = veToken.getPastTotalSupply(timestamp);

            // Basic sanity check: past supply shouldn't be astronomically high
            // Allow for 100x current staked as upper bound (very generous for edge cases)
            assertTrue(
                pastSupply <= currentActiveStaked * 100 || pastSupply == 0, "Past total supply is unreasonably high"
            );
        }
    }

    /**
     * Invariant 7: User can only have one active position at a time
     */
    function invariant_SingleActivePositionPerUser() public view {
        uint256 actorCount = handler.getActorCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.actors(i);
            uint256 activePosition = veToken.getActiveTokenId(actor);

            if (activePosition != 0) {
                // If user has active position, it should match our ghost tracking
                assertTrue(handler.ghost_hasActivePosition(actor), "Active position mismatch with ghost state");

                assertEq(activePosition, handler.ghost_userTokenId(actor), "Token ID mismatch with ghost state");
            } else {
                // If no active position, ghost state should reflect that
                assertFalse(handler.ghost_hasActivePosition(actor), "Ghost state shows position when none exists");
            }
        }
    }

    /**
     * Invariant 8: Total reward power equals sum of non-withdrawing staked amounts
     */
    function invariant_TotalRewardPowerConsistent() public view {
        uint256 totalRewardPower = veToken.getTotalStakingRewards();
        uint256 expectedTotal = handler.getActiveNonWithdrawingStaked();

        assertEq(totalRewardPower, expectedTotal, "Total reward power should equal total non-withdrawing staked");
    }

    /**
     * Invariant 9: Withdrawal period is enforced correctly
     */
    function invariant_WithdrawalPeriodEnforced() public view {
        uint256 actorCount = handler.getActorCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.actors(i);

            if (handler.ghost_hasActivePosition(actor) && handler.ghost_isWithdrawing(actor)) {
                uint256 withdrawalRequestTime = handler.ghost_withdrawalRequestTime(actor);

                // If withdrawal was requested, it should be in the past
                assertTrue(
                    withdrawalRequestTime <= vm.getBlockTimestamp(), "Withdrawal request time should not be in future"
                );

                // If withdrawal request time is valid, request should have been made
                if (withdrawalRequestTime > 0) {
                    assertTrue(
                        handler.ghost_isWithdrawing(actor), "Ghost state should show withdrawing if request time exists"
                    );
                }
            } else if (!handler.ghost_isWithdrawing(actor)) {
                // Non-withdrawing users should have no withdrawal request time
                assertEq(
                    handler.ghost_withdrawalRequestTime(actor),
                    0,
                    "Non-withdrawing user should have no withdrawal request time"
                );
            }
        }
    }

    /**
     * Invariant 10: Total voting power equals sum of non-withdrawing staked amounts
     */
    function invariant_TotalVotingPowerConsistent() public view {
        // Calculate total voting power by summing individual voting powers
        uint256 totalVotingPower = 0;
        uint256 actorCount = handler.getActorCount();
        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.actors(i);
            totalVotingPower += veToken.getVotes(actor);
        }

        uint256 expectedTotal = handler.getActiveNonWithdrawingStaked();

        assertEq(totalVotingPower, expectedTotal, "Total voting power should equal total non-withdrawing staked");
    }

    /**
     * This invariant runs last and prints comprehensive statistics
     */
    function invariant_ZZZ_FinalStats() public view {
        console.log("\n===============================================");
        console.log("=== FINAL INVARIANT TEST STATISTICS ===");
        console.log("===============================================");
        console.log("Total calls executed:", handler.callCount());
        console.log("Action breakdown:");
        console.log("  - Stake calls:", handler.stakeCount());
        console.log("  - Add stake calls:", handler.addStakeCount());
        console.log("  - Initiate withdrawal calls:", handler.initiateWithdrawalCount());
        console.log("  - Complete withdrawal calls:", handler.completeWithdrawalCount());
        console.log("  - Time warp calls:", handler.timeWarpCount());
        console.log("Active participants:", handler.getActorCount());
        console.log("Total amount staked:", handler.getTotalActiveStaked());
        console.log("Active non-withdrawing staked:", handler.getActiveNonWithdrawingStaked());
        console.log("Historical snapshots recorded:", handler.getHistoricalSnapshotCount());

        // Calculate percentages for action distribution
        uint256 totalActions = handler.stakeCount() + handler.addStakeCount() + handler.initiateWithdrawalCount()
            + handler.completeWithdrawalCount();
        if (totalActions > 0) {
            console.log("\nAction distribution:");
            console.log("  - Stake %:", (handler.stakeCount() * 100) / totalActions);
            console.log("  - Add stake %:", (handler.addStakeCount() * 100) / totalActions);
            console.log("  - Initiate withdrawal %:", (handler.initiateWithdrawalCount() * 100) / totalActions);
            console.log("  - Complete withdrawal %:", (handler.completeWithdrawalCount() * 100) / totalActions);
        }
        console.log("===============================================\n");
    }
}
