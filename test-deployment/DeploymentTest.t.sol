// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import {ZKC} from "../src/ZKC.sol";
import {veZKC} from "../src/veZKC.sol";
import {StakingRewards} from "../src/rewards/StakingRewards.sol";
import {ConfigLoader, DeploymentConfig} from "../script/Config.s.sol";

/// @title DeploymentTest
/// @notice Test designed to be run against a chain with an active deployment of ZKC contracts.
/// @notice Checks that the deployment matches what is recorded in the deployment.toml file.
contract DeploymentTest is Test {
    // Reference the vm address without needing to inherit from Script
    Vm constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    
    DeploymentConfig internal deployment;
    string internal deploymentKey;
    
    ZKC internal zkc;
    veZKC internal veZKCContract;
    StakingRewards internal stakingRewards;
    
    function setUp() external {
        // Load the deployment config
        (deployment, deploymentKey) = ConfigLoader.loadDeploymentConfig(VM);
        console2.log("Testing deployment:", deploymentKey);
        console2.log("Network name:", deployment.name);
        console2.log("Chain ID:", deployment.id);
        
        // Initialize contract references if addresses are set
        if (deployment.zkc != address(0)) {
            zkc = ZKC(deployment.zkc);
        }
        if (deployment.veZKC != address(0)) {
            veZKCContract = veZKC(deployment.veZKC);
        }
        if (deployment.stakingRewards != address(0)) {
            stakingRewards = StakingRewards(deployment.stakingRewards);
        }
    }
    
    function testZKCIsDeployed() external view {
        require(deployment.zkc != address(0), "ZKC address must be set in deployment.toml");
        require(_getCodeSize(deployment.zkc) > 0, "ZKC proxy must have non-empty bytecode");
        
        // Test that it's actually a ZKC contract
        require(bytes(zkc.name()).length > 0, "ZKC must have a name");
        require(bytes(zkc.symbol()).length > 0, "ZKC must have a symbol");
    }
    
    function testZKCImplementationIsDeployed() external view {
        require(deployment.zkcImpl != address(0), "ZKC implementation address must be set in deployment.toml");
        require(_getCodeSize(deployment.zkcImpl) > 0, "ZKC implementation must have non-empty bytecode");
    }
    
    function testZKCProxyImplementationMatches() external view {
        if (deployment.zkc != address(0) && deployment.zkcImpl != address(0)) {
            // Get implementation address from proxy
            address actualImpl = _getProxyImplementation(deployment.zkc);
            assertEq(actualImpl, deployment.zkcImpl, "ZKC proxy implementation must match deployment.toml");
        }
    }
    
    function testZKCAdminRole() external view {
        if (deployment.zkc != address(0) && deployment.zkcAdmin != address(0)) {
            IAccessControl accessControl = IAccessControl(deployment.zkc);
            assertTrue(
                accessControl.hasRole(zkc.ADMIN_ROLE(), deployment.zkcAdmin),
                "Admin must have ADMIN_ROLE on ZKC contract"
            );
        }
    }
    
    function testZKCInitialState() external view {
        if (deployment.zkc != address(0)) {
            // Test initial supply and minters are configured
            assertTrue(zkc.INITIAL_SUPPLY() > 0, "ZKC must have initial supply configured");
            assertTrue(zkc.initialMinter1() != address(0) || zkc.initialMinter2() != address(0), "ZKC must have an initial minter");
        }
    }
    
    function testVeZKCIsDeployed() external view {
        if (deployment.veZKC != address(0)) {
            require(_getCodeSize(deployment.veZKC) > 0, "veZKC proxy must have non-empty bytecode");
            
            // Test that it's actually a veZKC contract
            require(bytes(veZKCContract.name()).length > 0, "veZKC must have a name");
            require(bytes(veZKCContract.symbol()).length > 0, "veZKC must have a symbol");
        }
    }
    
    function testVeZKCImplementationIsDeployed() external view {
        if (deployment.veZKCImpl != address(0)) {
            require(_getCodeSize(deployment.veZKCImpl) > 0, "veZKC implementation must have non-empty bytecode");
        }
    }
    
    function testVeZKCProxyImplementationMatches() external view {
        if (deployment.veZKC != address(0) && deployment.veZKCImpl != address(0)) {
            address actualImpl = _getProxyImplementation(deployment.veZKC);
            assertEq(actualImpl, deployment.veZKCImpl, "veZKC proxy implementation must match deployment.toml");
        }
    }
    
    function testVeZKCAdminRole() external view {
        if (deployment.veZKC != address(0) && deployment.veZKCAdmin != address(0)) {
            IAccessControl accessControl = IAccessControl(deployment.veZKC);
            assertTrue(
                accessControl.hasRole(veZKCContract.ADMIN_ROLE(), deployment.veZKCAdmin),
                "Admin must have ADMIN_ROLE on veZKC contract"
            );
        }
    }
    
    function testVeZKCTokenReference() external view {
        if (deployment.veZKC != address(0) && deployment.zkc != address(0)) {
            assertEq(
                address(veZKCContract.zkcToken()), 
                deployment.zkc,
                "veZKC must reference correct ZKC token address"
            );
        }
    }
    
    function testStakingRewardsIsDeployed() external view {
        if (deployment.stakingRewards != address(0)) {
            require(_getCodeSize(deployment.stakingRewards) > 0, "StakingRewards proxy must have non-empty bytecode");
        }
    }
    
    function testStakingRewardsImplementationIsDeployed() external view {
        if (deployment.stakingRewardsImpl != address(0)) {
            require(_getCodeSize(deployment.stakingRewardsImpl) > 0, "StakingRewards implementation must have non-empty bytecode");
        }
    }
    
    function testStakingRewardsProxyImplementationMatches() external view {
        if (deployment.stakingRewards != address(0) && deployment.stakingRewardsImpl != address(0)) {
            address actualImpl = _getProxyImplementation(deployment.stakingRewards);
            assertEq(actualImpl, deployment.stakingRewardsImpl, "StakingRewards proxy implementation must match deployment.toml");
        }
    }
    
    function testStakingRewardsAdminRole() external view {
        if (deployment.stakingRewards != address(0) && deployment.stakingRewardsAdmin != address(0)) {
            IAccessControl accessControl = IAccessControl(deployment.stakingRewards);
            assertTrue(
                accessControl.hasRole(stakingRewards.ADMIN_ROLE(), deployment.stakingRewardsAdmin),
                "Admin must have ADMIN_ROLE on StakingRewards contract"
            );
        }
    }
    
    function testStakingRewardsTokenReferences() external view {
        if (deployment.stakingRewards != address(0)) {
            if (deployment.zkc != address(0)) {
                assertEq(
                    address(stakingRewards.zkc()),
                    deployment.zkc,
                    "StakingRewards must reference correct ZKC token address"
                );
            }
            if (deployment.veZKC != address(0)) {
                assertEq(
                    address(stakingRewards.veZKC()),
                    deployment.veZKC,
                    "StakingRewards must reference correct veZKC token address"
                );
            }
        }
    }

    function testStakingRewardsZkcAddressMatchesConfig() external view {
        if (deployment.stakingRewards != address(0) && deployment.zkc != address(0)) {
            assertEq(
                address(stakingRewards.zkc()),
                deployment.zkc,
                "StakingRewards zkc address must match deployment config"
            );
        }
    }

    function testStakingRewardsVeZKCAddressMatchesConfig() external view {
        if (deployment.stakingRewards != address(0) && deployment.veZKC != address(0)) {
            assertEq(
                address(stakingRewards.veZKC()),
                deployment.veZKC,
                "StakingRewards veZKC address must match deployment config"
            );
        }
    }

    function testZKCEpochFunctionsWorkAfterInitializeV3() external {
        if (deployment.zkc != address(0)) {
            // These functions should work after initializeV3 is called
            try zkc.getCurrentEpoch() returns (uint256 currentEpoch) {
                assertTrue(currentEpoch >= 0, "Current epoch should be valid");
            } catch {
                revert("getCurrentEpoch should work after initializeV3 in deployment");
            }

            try zkc.getCurrentEpochEndTime() returns (uint256 endTime) {
                assertTrue(endTime > block.timestamp, "Current epoch end time should be in future");
            } catch {
                revert("getCurrentEpochEndTime should work after initializeV3 in deployment");
            }

            try zkc.getEpochStartTime(0) returns (uint256 startTime) {
                assertTrue(startTime > 0 && startTime != type(uint256).max, "Epoch 0 start time should be set");
            } catch {
                revert("getEpochStartTime should work after initializeV3 in deployment");
            }

            try zkc.getEpochEndTime(0) returns (uint256 endTime) {
                assertTrue(endTime > zkc.getEpochStartTime(0), "Epoch end time should be after start time");
            } catch {
                revert("getEpochEndTime should work after initializeV3 in deployment");
            }
        }
    }

    function testZKCEmissionFunctionsWorkAfterInitializeV3() external {
        if (deployment.zkc != address(0)) {
            // These emission functions should work after initializeV3 is called
            try zkc.getPoVWEmissionsForEpoch(0) returns (uint256 povwEmissions) {
                assertTrue(povwEmissions > 0, "PoVW emissions should be positive");
            } catch {
                revert("getPoVWEmissionsForEpoch should work after initializeV3 in deployment");
            }

            try zkc.getStakingEmissionsForEpoch(0) returns (uint256 stakingEmissions) {
                assertTrue(stakingEmissions > 0, "Staking emissions should be positive");
            } catch {
                revert("getStakingEmissionsForEpoch should work after initializeV3 in deployment");
            }

            try zkc.getTotalPoVWEmissionsAtEpochStart(0) returns (uint256 totalPoVW) {
                assertTrue(totalPoVW >= 0, "Total PoVW emissions should be non-negative");
            } catch {
                revert("getTotalPoVWEmissionsAtEpochStart should work after initializeV3 in deployment");
            }

            try zkc.getTotalStakingEmissionsAtEpochStart(0) returns (uint256 totalStaking) {
                assertTrue(totalStaking >= 0, "Total staking emissions should be non-negative");
            } catch {
                revert("getTotalStakingEmissionsAtEpochStart should work after initializeV3 in deployment");
            }
        }
    }
    
    function testZKCMinterRoles() external view {
        if (deployment.zkc != address(0)) {
            IAccessControl accessControl = IAccessControl(deployment.zkc);
            
            // Test POVW minter role if configured
            if (deployment.povwMinter != address(0)) {
                assertTrue(
                    accessControl.hasRole(zkc.POVW_MINTER_ROLE(), deployment.povwMinter),
                    "POVW minter must have POVW_MINTER_ROLE on ZKC contract"
                );
            }
            
            // Test staking minter role if configured
            if (deployment.stakingMinter != address(0)) {
                assertTrue(
                    accessControl.hasRole(zkc.STAKING_MINTER_ROLE(), deployment.stakingMinter),
                    "Staking minter must have STAKING_MINTER_ROLE on ZKC contract"
                );
            }
        }
    }
    
    function testDeploymentConsistency() external view {
        // Test that all components reference each other correctly
        if (deployment.zkc != address(0) && deployment.veZKC != address(0)) {
            // veZKC should reference ZKC
            assertEq(
                address(veZKCContract.zkcToken()),
                deployment.zkc,
                "veZKC must reference deployed ZKC token"
            );
        }
        
        if (deployment.stakingRewards != address(0) && deployment.zkc != address(0) && deployment.veZKC != address(0)) {
            // StakingRewards should reference both ZKC and veZKC
            assertEq(
                address(stakingRewards.zkc()),
                deployment.zkc,
                "StakingRewards must reference deployed ZKC token"
            );
            assertEq(
                address(stakingRewards.veZKC()),
                deployment.veZKC,
                "StakingRewards must reference deployed veZKC token"
            );
        }
    }
    
    function testChainIdMatches() external view {
        assertEq(block.chainid, deployment.id, "Chain ID must match deployment configuration");
    }
    
    function testZKCPreviousImplementationTracking() external view {
        if (deployment.zkc != address(0) && deployment.zkcImplPrev != address(0)) {
            // Verify previous implementation has bytecode (could be rolled back to)
            require(_getCodeSize(deployment.zkcImplPrev) > 0, "Previous ZKC implementation must have non-empty bytecode");
            
            // Verify current and previous implementations are different
            assertFalse(
                deployment.zkcImpl == deployment.zkcImplPrev,
                "Current and previous ZKC implementations should be different"
            );
        }
    }
    
    function testVeZKCPreviousImplementationTracking() external view {
        if (deployment.veZKC != address(0) && deployment.veZKCImplPrev != address(0)) {
            // Verify previous implementation has bytecode (could be rolled back to)
            require(_getCodeSize(deployment.veZKCImplPrev) > 0, "Previous veZKC implementation must have non-empty bytecode");
            
            // Verify current and previous implementations are different  
            assertFalse(
                deployment.veZKCImpl == deployment.veZKCImplPrev,
                "Current and previous veZKC implementations should be different"
            );
        }
    }
    
    function testStakingRewardsPreviousImplementationTracking() external view {
        if (deployment.stakingRewards != address(0) && deployment.stakingRewardsImplPrev != address(0)) {
            // Verify previous implementation has bytecode (could be rolled back to)
            require(_getCodeSize(deployment.stakingRewardsImplPrev) > 0, "Previous StakingRewards implementation must have non-empty bytecode");
            
            // Verify current and previous implementations are different
            assertFalse(
                deployment.stakingRewardsImpl == deployment.stakingRewardsImplPrev,
                "Current and previous StakingRewards implementations should be different"
            );
        }
    }
    
    function testZKCIsV2OrV3() external view {
        if (deployment.zkc != address(0)) {
            // Check that STAKING_ALLOCATION_BPS is 2500 (25%) - this indicates V2/V3 version
            uint256 stakingAllocationBps = zkc.STAKING_ALLOCATION_BPS();
            assertEq(
                stakingAllocationBps,
                2500,
                "STAKING_ALLOCATION_BPS should be 2500 (25%) in ZKC V2/V3 version"
            );
            
            console2.log("ZKC STAKING_ALLOCATION_BPS:", stakingAllocationBps);
            console2.log("ZKC is deployed with V2/V3 version (25% staking allocation)");
        }
    }
    
    // ============ Helper Functions ============
    
    /// @notice Get the size of contract code at an address
    function _getCodeSize(address addr) internal view returns (uint256 size) {
        assembly {
            size := extcodesize(addr)
        }
    }
    
    /// @notice Get the implementation address from an ERC1967 proxy
    function _getProxyImplementation(address proxy) internal view returns (address impl) {
        // ERC1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        // Use vm.load to read the storage slot from the proxy contract
        bytes32 data = VM.load(proxy, slot);
        impl = address(uint160(uint256(data)));

        // If still zero, try calling implementation() function
        if (impl == address(0)) {
            (bool success, bytes memory returnData) = proxy.staticcall(
                abi.encodeWithSignature("implementation()")
            );
            if (success && returnData.length == 32) {
                impl = abi.decode(returnData, (address));
            }
        }
    }

    function testStakeAndClaimWithValueRecipient() external {
        require(deployment.zkc != address(0), "ZKC must be deployed");
        require(deployment.veZKC != address(0), "veZKC must be deployed");
        require(deployment.stakingRewards != address(0), "StakingRewards must be deployed");

        // Find a ZKC whale by checking the ZKC admin address (which should have tokens)
        address whale = deployment.zkcAdmin;
        if (whale == address(0)) {
            whale = deployment.zkcAdmin2;
        }
        require(whale != address(0), "Could not find whale address");

        uint256 whaleBalance = zkc.balanceOf(whale);
        address[3] memory whales = [deployment.zkcAdmin, address(0xb13573C6CEB505A7BDD4Fa3AD7b473c5c5d36b19), address(0x28C6c06298d514Db089934071355E5743bf21d60)];
        for (uint256 i = 0; i < whales.length; i++) {
            if (whales[i] != address(0)) {
                whale = whales[i];
                whaleBalance = zkc.balanceOf(whale);
                if (whaleBalance > 0) {
                    break;
                }
            }
        }
        require(whaleBalance > 0, "Whale must have ZKC tokens");

        // Use 10% of whale's balance for staking (or 100k ZKC, whichever is smaller)
        uint256 stakeAmount = whaleBalance / 10;
        if (stakeAmount > 100_000e18) {
            stakeAmount = 100_000e18;
        }
        require(stakeAmount > 0, "Stake amount must be positive");

        // Impersonate the whale
        vm.startPrank(whale);

        // Approve veZKC to spend ZKC
        zkc.approve(deployment.veZKC, stakeAmount);

        // Stake tokens
        uint256 tokenId = veZKCContract.stake(stakeAmount);
        console2.log("Staked with token ID:", tokenId);

        vm.stopPrank();

        // Get current epoch before warping
        uint256 currentEpoch = zkc.getCurrentEpoch();
        console2.log("Current epoch:", currentEpoch);

        // Warp forward past the current epoch (2 days + 1 hour to be safe)
        vm.warp(block.timestamp + 2 days + 1 hours);

        uint256 newEpoch = zkc.getCurrentEpoch();
        console2.log("New epoch after warp:", newEpoch);
        require(newEpoch > currentEpoch, "Must advance to next epoch");

        // Set up a value recipient address
        address valueRecipient = address(0xBEEF);
        uint256 recipientBalanceBefore = zkc.balanceOf(valueRecipient);
        console2.log("Value recipient balance before claim:", recipientBalanceBefore);

        // Claim rewards to the value recipient
        vm.startPrank(whale);
        uint256[] memory epochs = new uint256[](1);
        epochs[0] = currentEpoch;

        uint256 claimedAmount = stakingRewards.claimRewardsToRecipient(epochs, valueRecipient);
        console2.log("Claimed amount:", claimedAmount);

        vm.stopPrank();

        // Verify rewards were sent to value recipient
        uint256 recipientBalanceAfter = zkc.balanceOf(valueRecipient);
        console2.log("Value recipient balance after claim:", recipientBalanceAfter);

        assertEq(recipientBalanceAfter - recipientBalanceBefore, claimedAmount, "Recipient should receive claimed rewards");
        assertTrue(claimedAmount > 0, "Should have claimed some rewards");

        console2.log("Successfully claimed", claimedAmount, "ZKC to value recipient");

        // Attempt to claim again for the same epoch - should revert with AlreadyClaimed
        vm.startPrank(whale);
        vm.expectRevert(abi.encodeWithSignature("AlreadyClaimed(uint256)", currentEpoch));
        stakingRewards.claimRewardsToRecipient(epochs, valueRecipient);
        vm.stopPrank();

        // Verify that attempting to claim to a different recipient also fails
        address differentRecipient = address(0xCAFE);
        vm.startPrank(whale);
        vm.expectRevert(abi.encodeWithSignature("AlreadyClaimed(uint256)", currentEpoch));
        stakingRewards.claimRewardsToRecipient(epochs, differentRecipient);
        vm.stopPrank();

        // Verify balances haven't changed after failed claim attempts
        assertEq(zkc.balanceOf(valueRecipient), recipientBalanceAfter, "Value recipient balance should not change after failed claim");
        assertEq(zkc.balanceOf(differentRecipient), 0, "Different recipient should have zero balance");

        console2.log("Verified that double-claiming is prevented");
    }
}