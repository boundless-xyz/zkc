// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ConfigLoader, DeploymentConfig} from "./Config.s.sol";
import {BaseDeployment} from "./BaseDeployment.s.sol";
import {ZKC} from "../src/ZKC.sol";

/**
 * Sample Usage for setting POVW minter role:
 *
 * export CHAIN_KEY="anvil"
 * export POVW_MINTER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:UpdatePOVWMinter \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpdatePOVWMinter is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");

        address povwMinter = vm.envAddress("POVW_MINTER");
        require(povwMinter != address(0), "POVW_MINTER environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        ZKC zkcContract = ZKC(config.zkc);
        bytes32 povwMinterRole = zkcContract.POVW_MINTER_ROLE();

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing grantRole calldata for Safe execution");
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("POVW Minter: ", povwMinter);
            console2.log("Role: POVW_MINTER_ROLE");

            // Print Gnosis Safe transaction info for grantRole
            bytes memory grantRoleCallData =
                abi.encodeWithSignature("grantRole(bytes32,address)", povwMinterRole, povwMinter);
            console2.log("================================");
            console2.log("================================");
            console2.log("=== GNOSIS SAFE GRANT ROLE INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(povwMinterRole);
            console2.log("Account: ", povwMinter);
            console2.log("Calldata:");
            console2.logBytes(grantRoleCallData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)");
            console2.log("   - role: POVW_MINTER_ROLE");
            console2.log("   - account: ", povwMinter);
            console2.log("   - sender: <Safe address>");
            console2.log("");
            console2.log("Expected Event in Raw Hex:");
            console2.log("Event Signature: RoleGranted(bytes32,address,address)");
            // RoleGranted event signature: keccak256("RoleGranted(bytes32,address,address)")
            bytes32 eventSignature = 0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d;
            console2.log("topics[0] (event signature):");
            console2.logBytes32(eventSignature);
            console2.log("topics[1] (role - indexed):");
            console2.logBytes32(povwMinterRole);
            console2.log("topics[2] (account - indexed): 0x000000000000000000000000", povwMinter);
            console2.log("topics[3] (sender - indexed): <Safe address as bytes32>");
            console2.log("data: 0x (empty - all parameters are indexed)");
            console2.log("=====================================");

            console2.log("================================================");
            console2.log("POVW Minter Grant Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            IAccessControl accessControl = IAccessControl(config.zkc);

            // Check if caller has admin role
            require(accessControl.hasRole(zkcContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE");

            // Grant POVW_MINTER_ROLE
            accessControl.grantRole(povwMinterRole, povwMinter);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("POVW Minter: ", povwMinter);
            console2.log("POVW_MINTER_ROLE granted: ", accessControl.hasRole(povwMinterRole, povwMinter));
            console2.log("================================================");
            console2.log("POVW Minter Role Updated Successfully");
        }

        // Update deployment.toml with the new minter (always do this)
        _updateDeploymentConfig(deploymentKey, "povw-minter", povwMinter);
    }
}

/**
 * Sample Usage for setting Staking minter role:
 *
 * export CHAIN_KEY="anvil"
 * export STAKING_MINTER="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
 *
 * forge script script/Update.s.sol:UpdateStakingMinter \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpdateStakingMinter is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");

        address stakingMinter = vm.envAddress("STAKING_MINTER");
        require(stakingMinter != address(0), "STAKING_MINTER environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        ZKC zkcContract = ZKC(config.zkc);
        bytes32 stakingMinterRole = zkcContract.STAKING_MINTER_ROLE();

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing grantRole calldata for Safe execution");
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("Staking Minter: ", stakingMinter);
            console2.log("Role: STAKING_MINTER_ROLE");

            // Print Gnosis Safe transaction info for grantRole
            bytes memory grantRoleCallData =
                abi.encodeWithSignature("grantRole(bytes32,address)", stakingMinterRole, stakingMinter);
            console2.log("================================");
            console2.log("================================");
            console2.log("=== GNOSIS SAFE GRANT ROLE INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(stakingMinterRole);
            console2.log("Account: ", stakingMinter);
            console2.log("Calldata:");
            console2.logBytes(grantRoleCallData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)");
            console2.log("   - role: STAKING_MINTER_ROLE");
            console2.log("   - account: ", stakingMinter);
            console2.log("   - sender: <Safe address>");
            console2.log("");
            console2.log("Expected Event in Raw Hex:");
            console2.log("Event Signature: RoleGranted(bytes32,address,address)");
            // RoleGranted event signature: keccak256("RoleGranted(bytes32,address,address)")
            bytes32 eventSignature = 0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d;
            console2.log("topics[0] (event signature):");
            console2.logBytes32(eventSignature);
            console2.log("topics[1] (role - indexed):");
            console2.logBytes32(stakingMinterRole);
            console2.log("topics[2] (account - indexed): 0x000000000000000000000000", stakingMinter);
            console2.log("topics[3] (sender - indexed): <Safe address as bytes32>");
            console2.log("data: 0x (empty - all parameters are indexed)");
            console2.log("=====================================");

            console2.log("================================================");
            console2.log("Staking Minter Grant Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            IAccessControl accessControl = IAccessControl(config.zkc);

            // Check if caller has admin role
            require(accessControl.hasRole(zkcContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE");

            // Grant STAKING_MINTER_ROLE
            accessControl.grantRole(stakingMinterRole, stakingMinter);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("Staking Minter: ", stakingMinter);
            console2.log("STAKING_MINTER_ROLE granted: ", accessControl.hasRole(stakingMinterRole, stakingMinter));
            console2.log("================================================");
            console2.log("Staking Minter Role Updated Successfully");
        }

        // Update deployment.toml with the new minter (always do this)
        _updateDeploymentConfig(deploymentKey, "staking-minter", stakingMinter);
    }
}
