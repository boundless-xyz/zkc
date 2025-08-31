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
    
    function testAdminIsSet() external view {
        require(deployment.zkcAdmin != address(0), "ZKC admin address must be set in deployment.toml");
        require(deployment.veZKCAdmin != address(0), "veZKC admin address must be set in deployment.toml");
        require(deployment.stakingRewardsAdmin != address(0), "StakingRewards admin address must be set in deployment.toml");
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
    
    function testDeploymentCommitIsSet() external view {
        // Only require commit for mainnet deployments
        if (deployment.id == 1) { // Ethereum mainnet
            require(bytes(deployment.deploymentCommit).length > 0, "Deployment commit must be set for mainnet");
        }
    }
    
    // ============ Rollback Support Tests ============
    
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
}