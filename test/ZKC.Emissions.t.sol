// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ZKC.t.sol";
import "../src/libraries/Supply.sol";

contract ZKCEmissionsTest is ZKCTest {
    function setUp() public {
        deployZKC();
    }
    
    function testGetEmissionsForEpoch() public {
        // Test basic emissions
        uint256 emission1 = zkc.getEmissionsForEpoch(1);
        uint256 emission100 = zkc.getEmissionsForEpoch(100);
        
        assertGt(emission1, 0, "Emissions should be positive");
        assertGt(emission100, 0, "Emissions should be positive");
        
        // Test delegation to Supply library
        assertEq(zkc.getEmissionsForEpoch(50), Supply.getEmissionsForEpoch(50));
    }
    
    function testGetPoVWEmissionsForEpoch() public {
        uint256 totalEmission = zkc.getEmissionsForEpoch(1);
        uint256 povwEmission = zkc.getPoVWEmissionsForEpoch(1);
        
        // Should be 75% of total
        uint256 expected = (totalEmission * 7500) / 10000;
        assertEq(povwEmission, expected);
    }
    
    function testGetStakingEmissionsForEpoch() public {
        uint256 totalEmission = zkc.getEmissionsForEpoch(1);
        uint256 stakingEmission = zkc.getStakingEmissionsForEpoch(1);
        
        // Should be 25% of total
        uint256 expected = (totalEmission * 2500) / 10000;
        assertEq(stakingEmission, expected);
    }
    
    function testEmissionsSumToTotal() public {
        uint256 total = zkc.getEmissionsForEpoch(1);
        uint256 povw = zkc.getPoVWEmissionsForEpoch(1);
        uint256 staking = zkc.getStakingEmissionsForEpoch(1);
        
        assertEq(povw + staking, total);
    }
    
    function testGetPoVWRemainingForEpoch() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getPoVWEmissionsForEpoch(epoch);
        
        // Initially should equal full allocation
        assertEq(zkc.getPoVWUnclaimedForEpoch(epoch), allocation);
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        // Mint half
        uint256 mintAmount = allocation / 2;
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        // Should have half remaining
        assertEq(zkc.getPoVWUnclaimedForEpoch(epoch), allocation - mintAmount);
    }
    
    function testGetStakingRemainingForEpoch() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        // Initially should equal full allocation
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), allocation);
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        // Mint third
        uint256 mintAmount = allocation / 3;
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
        
        // Should have 2/3 remaining
        assertEq(zkc.getStakingUnclaimedForEpoch(epoch), allocation - mintAmount);
    }
    
    function testMintPoVWRewardsForRecipient() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 mintAmount = allocation / 4;
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        // Check balance increased
        assertEq(zkc.balanceOf(user), balanceBefore + mintAmount);
        
        // Check tracking updated
        assertEq(zkc.epochPoVWMinted(epoch), mintAmount);
    }
    
    function testMintStakingRewardsForRecipient() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getStakingEmissionsForEpoch(epoch);
        uint256 mintAmount = allocation / 4;
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
        
        // Check balance increased
        assertEq(zkc.balanceOf(user), balanceBefore + mintAmount);
        
        // Check tracking updated
        assertEq(zkc.epochStakingMinted(epoch), mintAmount);
    }
    
    function testMintRewardEvents() public {
        uint256 epoch = 1;
        uint256 mintAmount = 1000 * 10**18;
        
        // Move to next epoch to allow minting
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        
        // Test PoVW event
        vm.expectEmit(true, false, false, true);
        emit ZKC.PoVWRewardsClaimed(user, epochs, amounts);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        // Test staking event
        vm.expectEmit(true, false, false, true);
        emit ZKC.StakingRewardsClaimed(user, epochs, amounts);
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
    }
    
    function testMintRewardRevertCurrentEpoch() public {
        uint256 currentEpoch = zkc.getCurrentEpoch();
        uint256 mintAmount = 1000 * 10**18;
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, currentEpoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
    }
    
    function testMintRewardRevertExceedsAllocation() public {
        uint256 epoch = 1;
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        uint256 povwAllocation = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 stakingAllocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        (uint256[] memory povwAmounts, uint256[] memory epochs1) = _buildSingleArrayInputs(povwAllocation + 1, epoch);
        (uint256[] memory stakingAmounts, uint256[] memory epochs2) = _buildSingleArrayInputs(stakingAllocation + 1, epoch);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, povwAmounts, epochs1);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, stakingAmounts, epochs2);
    }
    
    function testMintRewardRevertUnauthorized() public {
        uint256 epoch = 1;
        uint256 mintAmount = 1000 * 10**18;
        
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        (uint256[] memory amounts, uint256[] memory epochs) = _buildSingleArrayInputs(mintAmount, epoch);
        
        vm.expectRevert();
        vm.prank(user);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        vm.expectRevert();
        vm.prank(user);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);

        vm.expectRevert();
        vm.prank(stakingMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);

        vm.expectRevert();
        vm.prank(povwMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
    }

    function testMintPoVWRewardsForRecipientBatch() public {
        uint256[] memory epochs = new uint256[](3);
        epochs[0] = 1;
        epochs[1] = 2;
        epochs[2] = 3;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = zkc.getPoVWEmissionsForEpoch(1) / 4;
        amounts[1] = zkc.getPoVWEmissionsForEpoch(2) / 3;
        amounts[2] = zkc.getPoVWEmissionsForEpoch(3) / 2;
        
        // Move to epoch 4 to allow minting previous epochs
        vm.warp(deploymentTime + 4 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        uint256 expectedTotal = amounts[0] + amounts[1] + amounts[2];
        
        vm.expectEmit(true, false, false, true);
        emit ZKC.PoVWRewardsClaimed(user, epochs, amounts);
        
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        // Check balance increased by total
        assertEq(zkc.balanceOf(user), balanceBefore + expectedTotal);
        
        // Check tracking updated for each epoch
        assertEq(zkc.epochPoVWMinted(1), amounts[0]);
        assertEq(zkc.epochPoVWMinted(2), amounts[1]);
        assertEq(zkc.epochPoVWMinted(3), amounts[2]);
    }

    function testMintStakingRewardsForRecipientBatch() public {
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = 1;
        epochs[1] = 2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = zkc.getStakingEmissionsForEpoch(1) / 5;
        amounts[1] = zkc.getStakingEmissionsForEpoch(2) / 6;
        
        // Move to epoch 3 to allow minting previous epochs
        vm.warp(deploymentTime + 3 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        uint256 expectedTotal = amounts[0] + amounts[1];
        
        vm.expectEmit(true, false, false, true);
        emit ZKC.StakingRewardsClaimed(user, epochs, amounts);
        
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
        
        // Check balance increased by total
        assertEq(zkc.balanceOf(user), balanceBefore + expectedTotal);
        
        // Check tracking updated for each epoch
        assertEq(zkc.epochStakingMinted(1), amounts[0]);
        assertEq(zkc.epochStakingMinted(2), amounts[1]);
    }

    function testBatchRewardsMismatchedArrayLength() public {
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = 1;
        epochs[1] = 2;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1000 * 10**18;
        amounts[1] = 2000 * 10**18;
        amounts[2] = 3000 * 10**18;
        
        vm.warp(deploymentTime + 3 * zkc.EPOCH_DURATION() + 1);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.InvalidInputLength.selector));
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.InvalidInputLength.selector));
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
    }

    function testBatchRewardsCurrentEpochReverts() public {
        vm.warp(deploymentTime + 5 * zkc.EPOCH_DURATION() + 1);
        uint256 currentEpoch = zkc.getCurrentEpoch();
        
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = currentEpoch - 1;
        epochs[1] = currentEpoch; // This should cause revert
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**18;
        amounts[1] = 2000 * 10**18;
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochNotEnded.selector, currentEpoch));
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
    }

    function testBatchRewardsAllocationExceeded() public {
        uint256 epoch = 1;
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        uint256 povwAllocation = zkc.getPoVWEmissionsForEpoch(epoch);
        uint256 stakingAllocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        uint256[] memory epochs = new uint256[](2);
        epochs[0] = epoch;
        epochs[1] = epoch;
        
        uint256[] memory povwAmounts = new uint256[](2);
        povwAmounts[0] = povwAllocation / 2 + 1;
        povwAmounts[1] = povwAllocation / 2 + 1; // Total exceeds allocation
        
        uint256[] memory stakingAmounts = new uint256[](2);
        stakingAmounts[0] = stakingAllocation / 2 + 1;
        stakingAmounts[1] = stakingAllocation / 2 + 1; // Total exceeds allocation
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, povwAmounts, epochs);
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, stakingAmounts, epochs);
    }

    function testBatchRewardsUnauthorized() public {
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = 1;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**18;
        
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        // Test unauthorized user
        vm.expectRevert();
        vm.prank(user);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        vm.expectRevert();
        vm.prank(user);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
        
        // Test wrong minter role
        vm.expectRevert();
        vm.prank(stakingMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        vm.expectRevert();
        vm.prank(povwMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
    }

    function testBatchRewardsEmptyArrays() public {
        uint256[] memory epochs = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);
        
        vm.warp(deploymentTime + 2 * zkc.EPOCH_DURATION() + 1);
        
        uint256 balanceBefore = zkc.balanceOf(user);
        
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
        
        // Balance should be unchanged
        assertEq(zkc.balanceOf(user), balanceBefore);
    }

    // Helper function to create arrays for gas testing
    function _buildArraysForGasTest(uint256 size, uint256 baseAmount) internal pure returns (uint256[] memory amounts, uint256[] memory epochs) {
        amounts = new uint256[](size);
        epochs = new uint256[](size);
        
        // Start from epoch 91 (halfway through year) for more realistic testing
        for (uint256 i = 0; i < size; i++) {
            amounts[i] = baseAmount;
            epochs[i] = 91 + i; // Start from epoch 91
        }
    }

    function benchMintPoVWRewards(uint256 batchSize, string memory snapshot) public {
        // Move to epoch beyond batch size + 91 to allow minting all epochs starting from 91
        vm.warp(deploymentTime + (91 + batchSize + 1) * zkc.EPOCH_DURATION() + 1);
        
        uint256 baseAmount = 1000 * 10**18;
        (uint256[] memory amounts, uint256[] memory epochs) = _buildArraysForGasTest(batchSize, baseAmount);
        
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForRecipient(user, amounts, epochs);
        vm.snapshotGasLastCall(string.concat("mintPoVWRewardsForRecipient: batch of ", snapshot));
    }

    function benchMintStakingRewards(uint256 batchSize, string memory snapshot) public {
        // Move to epoch beyond batch size + 91 to allow minting all epochs starting from 91
        vm.warp(deploymentTime + (91 + batchSize + 1) * zkc.EPOCH_DURATION() + 1);
        
        uint256 baseAmount = 1000 * 10**18;
        (uint256[] memory amounts, uint256[] memory epochs) = _buildArraysForGasTest(batchSize, baseAmount);
        
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForRecipient(user, amounts, epochs);
        vm.snapshotGasLastCall(string.concat("mintStakingRewardsForRecipient: batch of ", snapshot));
    }


    // Test new multi-recipient methods
    function testMintPoVWRewardsForEpoch() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getPoVWEmissionsForEpoch(epoch);
        
        // Set up multiple recipients
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");  
        address charlie = makeAddr("charlie");
        
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;  
        recipients[2] = charlie;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = allocation / 3;
        amounts[1] = allocation / 3;
        amounts[2] = allocation / 3;
        
        // Advance past epoch
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        // Record initial balances
        uint256 aliceBalanceBefore = zkc.balanceOf(alice);
        uint256 bobBalanceBefore = zkc.balanceOf(bob);
        uint256 charlieBalanceBefore = zkc.balanceOf(charlie);
        
        // Mint to multiple recipients
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForEpoch(epoch, recipients, amounts);
        
        // Verify each recipient received their amount
        assertEq(zkc.balanceOf(alice), aliceBalanceBefore + amounts[0], "Alice should receive her allocation");
        assertEq(zkc.balanceOf(bob), bobBalanceBefore + amounts[1], "Bob should receive his allocation");
        assertEq(zkc.balanceOf(charlie), charlieBalanceBefore + amounts[2], "Charlie should receive his allocation");
        
        // Verify epoch tracking
        uint256 totalMinted = amounts[0] + amounts[1] + amounts[2];
        assertEq(zkc.epochPoVWMinted(epoch), totalMinted, "Epoch tracking should reflect total minted");
    }

    function testMintStakingRewardsForEpoch() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getStakingEmissionsForEpoch(epoch);
        
        // Set up multiple recipients with different amounts
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = allocation * 2 / 3;
        amounts[1] = allocation / 3;
        
        // Advance past epoch
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        // Record initial balances
        uint256 aliceBalanceBefore = zkc.balanceOf(alice);
        uint256 bobBalanceBefore = zkc.balanceOf(bob);
        
        // Mint to multiple recipients
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForEpoch(epoch, recipients, amounts);
        
        // Verify each recipient received their amount
        assertEq(zkc.balanceOf(alice), aliceBalanceBefore + amounts[0], "Alice should receive her allocation");
        assertEq(zkc.balanceOf(bob), bobBalanceBefore + amounts[1], "Bob should receive his allocation");
        
        // Verify epoch tracking
        uint256 totalMinted = amounts[0] + amounts[1];
        assertEq(zkc.epochStakingMinted(epoch), totalMinted, "Epoch tracking should reflect total minted");
    }

    function testMintForEpochArrayLengthMismatch() public {
        uint256 epoch = 1;
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        
        uint256[] memory amounts = new uint256[](3); // Different length
        amounts[0] = 1000;
        amounts[1] = 1000;
        amounts[2] = 1000;
        
        vm.expectRevert(ZKC.InvalidInputLength.selector);
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForEpoch(epoch, recipients, amounts);
    }

    function testMintForEpochAllocationExceeded() public {
        uint256 epoch = 1;
        uint256 allocation = zkc.getPoVWEmissionsForEpoch(epoch);
        
        vm.warp(zkc.getEpochStartTime(epoch + 1));
        
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = allocation / 2 + 1;
        amounts[1] = allocation / 2 + 1; // Total exceeds allocation
        
        vm.expectRevert(abi.encodeWithSelector(ZKC.EpochAllocationExceeded.selector, epoch));
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForEpoch(epoch, recipients, amounts);
    }

    // Helper function to create recipient/amount arrays for ForEpoch gas testing
    function _buildArraysForEpochGasTest(uint256 recipientCount, uint256 baseAmount) internal pure returns (address[] memory recipients, uint256[] memory amounts) {
        recipients = new address[](recipientCount);
        amounts = new uint256[](recipientCount);
        
        for (uint256 i = 0; i < recipientCount; i++) {
            recipients[i] = address(uint160(0x1000 + i)); // Generate unique addresses
            amounts[i] = baseAmount;
        }
    }

    function benchMintPoVWRewardsForEpoch(uint256 recipientCount, string memory snapshot) public {
        // Test around halfway through the year (epoch ~91 of 182 per year)
        uint256 epoch = 91;
        // Move to epoch 92 to allow minting for epoch 91
        vm.warp(deploymentTime + 92 * zkc.EPOCH_DURATION() + 1);
        
        // Use a smaller base amount to avoid exceeding epoch allocation with many recipients
        uint256 baseAmount = 100 * 10**18;
        (address[] memory recipients, uint256[] memory amounts) = _buildArraysForEpochGasTest(recipientCount, baseAmount);
        
        vm.prank(povwMinter);
        zkc.mintPoVWRewardsForEpoch(epoch, recipients, amounts);
        vm.snapshotGasLastCall(string.concat("mintPoVWRewardsForEpoch: ", snapshot, " recipients"));
    }

    function benchMintStakingRewardsForEpoch(uint256 recipientCount, string memory snapshot) public {
        // Test around halfway through the year (epoch ~91 of 182 per year)
        uint256 epoch = 91;
        // Move to epoch 92 to allow minting for epoch 91
        vm.warp(deploymentTime + 92 * zkc.EPOCH_DURATION() + 1);
        
        // Use a smaller base amount for staking (25% allocation vs 75% for PoVW)
        // Scale down further for large recipient counts
        uint256 baseAmount = recipientCount >= 1000 ? 10 * 10**18 : 100 * 10**18;
        (address[] memory recipients, uint256[] memory amounts) = _buildArraysForEpochGasTest(recipientCount, baseAmount);
        
        vm.prank(stakingMinter);
        zkc.mintStakingRewardsForEpoch(epoch, recipients, amounts);
        vm.snapshotGasLastCall(string.concat("mintStakingRewardsForEpoch: ", snapshot, " recipients"));
    }

    // Benchmark tests for ForRecipient methods (existing pattern)
    function testBenchMintPoVWRewardsForRecipient001() public {
        benchMintPoVWRewards(1, "0001");
    }

    function testBenchMintPoVWRewardsForRecipient015() public {
        benchMintPoVWRewards(15, "0015");
    }

    function testBenchMintPoVWRewardsForRecipient030() public {
        benchMintPoVWRewards(30, "0030");
    }

    function testBenchMintStakingRewardsForRecipient001() public {
        benchMintStakingRewards(1, "0001");
    }

    function testBenchMintStakingRewardsForRecipient015() public {
        benchMintStakingRewards(15, "0015");
    }

    function testBenchMintStakingRewardsForRecipient030() public {
        benchMintStakingRewards(30, "0030");
    }

    // Benchmark tests for ForEpoch methods (new pattern)
    function testBenchMintPoVWRewardsForEpoch050() public {
        benchMintPoVWRewardsForEpoch(50, "0050");
    }

    function testBenchMintPoVWRewardsForEpoch250() public {
        benchMintPoVWRewardsForEpoch(250, "0250");
    }

    function testBenchMintPoVWRewardsForEpoch1000() public {
        benchMintPoVWRewardsForEpoch(1000, "1000");
    }

    function testBenchMintStakingRewardsForEpoch050() public {
        benchMintStakingRewardsForEpoch(50, "0050");
    }

    function testBenchMintStakingRewardsForEpoch250() public {
        benchMintStakingRewardsForEpoch(250, "0250");
    }

    function testBenchMintStakingRewardsForEpoch1000() public {
        benchMintStakingRewardsForEpoch(1000, "1000");
    }
}