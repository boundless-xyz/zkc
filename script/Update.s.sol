// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ConfigLoader, DeploymentConfig} from "./Config.s.sol";
import {BaseDeployment} from "./BaseDeployment.s.sol";
import {ZKC} from "../src/ZKC.sol";
import {SupplyCalculator} from "../src/calculators/SupplyCalculator.sol";
import {veZKC} from "../src/veZKC.sol";
import {StakingRewards} from "../src/rewards/StakingRewards.sol";

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

/**
 * Sample Usage for updating SupplyCalculator unlocked value:
 *
 * # Direct execution:
 * export CHAIN_KEY="anvil"
 * export NEW_UNLOCKED="750000000000000000000000000"  # 750M tokens
 *
 * forge script script/Update.s.sol:UpdateSupplyCalculatorUnlocked \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 *
 * # Gnosis Safe execution (print call data only):
 * export CHAIN_KEY="anvil"
 * export NEW_UNLOCKED="750000000000000000000000000"  # 750M tokens
 * export GNOSIS_EXECUTE=true
 *
 * forge script script/Update.s.sol:UpdateSupplyCalculatorUnlocked \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpdateSupplyCalculatorUnlocked is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.supplyCalculator != address(0), "SupplyCalculator address not set in deployment.toml");

        // Get new unlocked value from environment
        uint256 newUnlocked = vm.envUint("NEW_UNLOCKED");
        require(newUnlocked > 0, "NEW_UNLOCKED must be greater than 0");

        // Check for Gnosis Safe execution mode
        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);

        // Get the contract instance
        SupplyCalculator supplyCalculator = SupplyCalculator(config.supplyCalculator);

        // Get current values for logging
        uint256 currentUnlocked = supplyCalculator.unlocked();
        uint256 currentCirculatingSupply = supplyCalculator.circulatingSupply();

        console2.log("================================================");
        console2.log("Current unlocked amount: ", currentUnlocked);
        console2.log("Current unlocked amount (in tokens): ", currentUnlocked / 10 ** 18);
        console2.log("Current circulating supply: ", currentCirculatingSupply);
        console2.log("Current circulating supply (in tokens): ", currentCirculatingSupply / 10 ** 18);
        console2.log("================================================");

        if (gnosisExecute) {
            // Print Gnosis Safe transaction info for manual execution
            _printGnosisSafeInfo(config.supplyCalculator, newUnlocked);

            // Calculate expected new circulating supply for display
            uint256 expectedNewCirculatingSupply = currentCirculatingSupply - currentUnlocked + newUnlocked;

            console2.log("Expected after update:");
            console2.log("New unlocked amount: ", newUnlocked);
            console2.log("New unlocked amount (in tokens): ", newUnlocked / 10 ** 18);
            console2.log("New circulating supply: ", expectedNewCirculatingSupply);
            console2.log("New circulating supply (in tokens): ", expectedNewCirculatingSupply / 10 ** 18);
            console2.log("================================================");
        } else {
            vm.startBroadcast();

            // Update the unlocked value
            supplyCalculator.updateUnlockedValue(newUnlocked);

            // Get updated values
            uint256 updatedUnlocked = supplyCalculator.unlocked();
            uint256 updatedCirculatingSupply = supplyCalculator.circulatingSupply();

            vm.stopBroadcast();

            console2.log("Updated unlocked value!");
            console2.log("================================================");
            console2.log("New unlocked amount: ", updatedUnlocked);
            console2.log("New unlocked amount (in tokens): ", updatedUnlocked / 10 ** 18);
            console2.log("New circulating supply: ", updatedCirculatingSupply);
            console2.log("New circulating supply (in tokens): ", updatedCirculatingSupply / 10 ** 18);
            console2.log("================================================");
            console2.log("Change in unlocked: ", newUnlocked > currentUnlocked ? "+" : "-");
            if (newUnlocked > currentUnlocked) {
                console2.log("  Amount increased: ", (newUnlocked - currentUnlocked) / 10 ** 18, " tokens");
            } else {
                console2.log("  Amount decreased: ", (currentUnlocked - newUnlocked) / 10 ** 18, " tokens");
            }
        }
    }

    /// @notice Print Gnosis Safe transaction information for manual updates
    /// @param targetAddress The SupplyCalculator contract address (target for Gnosis Safe)
    /// @param newUnlocked The new unlocked value to set
    function _printGnosisSafeInfo(address targetAddress, uint256 newUnlocked) internal pure {
        console2.log("================================");
        console2.log("================================");
        console2.log("=== GNOSIS SAFE UPDATE INFO ===");
        console2.log("Target Address (To): ", targetAddress);
        console2.log("Function: updateUnlockedValue(uint256)");
        console2.log("New Unlocked Value: ", newUnlocked);
        console2.log("New Unlocked Value (in tokens): ", newUnlocked / 10 ** 18);

        bytes memory callData = abi.encodeWithSignature("updateUnlockedValue(uint256)", newUnlocked);
        console2.log("");
        console2.log("Calldata:");
        console2.logBytes(callData);
        console2.log("");
        console2.log("Expected Events on Successful Execution:");
        console2.log("1. UnlockedValueUpdated(uint256 oldValue, uint256 newValue)");
        console2.log("   - newValue: ", newUnlocked);
        console2.log("================================");
    }
}

/**
 * Sample Usage for removing POVW minter role:
 *
 * export CHAIN_KEY="anvil"
 * export POVW_MINTER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:RemovePOVWMinter \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RemovePOVWMinter is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");

        // Get POVW minter address from environment
        address povwMinter = vm.envAddress("POVW_MINTER");
        require(povwMinter != address(0), "POVW_MINTER environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        ZKC zkcContract = ZKC(config.zkc);
        bytes32 povwMinterRole = zkcContract.POVW_MINTER_ROLE();

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing revokeRole calldata for Safe execution");
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("POVW Minter: ", povwMinter);
            console2.log("Role: POVW_MINTER_ROLE");

            // Print Gnosis Safe transaction info for revokeRole
            bytes memory revokeRoleCallData =
                abi.encodeWithSignature("revokeRole(bytes32,address)", povwMinterRole, povwMinter);
            console2.log("================================");
            console2.log("================================");
            console2.log("=== GNOSIS SAFE REVOKE ROLE INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: revokeRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(povwMinterRole);
            console2.log("Account: ", povwMinter);
            console2.log("Calldata:");
            console2.logBytes(revokeRoleCallData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender)");
            console2.log("   - role: POVW_MINTER_ROLE");
            console2.log("   - account: ", povwMinter);
            console2.log("   - sender: <Safe address>");
            console2.log("");
            console2.log("Expected Event in Raw Hex:");
            console2.log("Event Signature: RoleRevoked(bytes32,address,address)");
            // RoleRevoked event signature: keccak256("RoleRevoked(bytes32,address,address)")
            bytes32 eventSignature = 0xf6391f5c32d9c69d2a47ea670b442974b53935d1edc7fd64eb21e047a839171b;
            console2.log("topics[0] (event signature):");
            console2.logBytes32(eventSignature);
            console2.log("topics[1] (role - indexed):");
            console2.logBytes32(povwMinterRole);
            console2.log("topics[2] (account - indexed): 0x000000000000000000000000", povwMinter);
            console2.log("topics[3] (sender - indexed): <Safe address as bytes32>");
            console2.log("data: 0x (empty - all parameters are indexed)");
            console2.log("=====================================");

            console2.log("================================================");
            console2.log("POVW Minter Revoke Role Calldata Ready");
        } else {
            vm.startBroadcast();

            IAccessControl accessControl = IAccessControl(config.zkc);

            // Revoke POVW_MINTER_ROLE
            accessControl.revokeRole(povwMinterRole, povwMinter);

            vm.stopBroadcast();

            console2.log("POVW Minter Role Removed Successfully");
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("POVW Minter: ", povwMinter);
            console2.log("POVW_MINTER_ROLE revoked: ", !accessControl.hasRole(povwMinterRole, povwMinter));
            console2.log("================================================");
            console2.log("POVW Minter Role Removed Successfully");
        }

        // Clear deployment.toml entry for the removed minter (always do this)
        _updateDeploymentConfig(deploymentKey, "povw-minter", address(0));
    }
}

/**
 * Sample Usage for adding admin to ZKC:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_ADD="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:AddZKCAdmin \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract AddZKCAdmin is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");
        address adminToAdd = vm.envAddress("ADMIN_TO_ADD");
        require(adminToAdd != address(0), "ADMIN_TO_ADD environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        ZKC zkcContract = ZKC(config.zkc);
        bytes32 adminRole = zkcContract.ADMIN_ROLE();

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing grantRole calldata for Safe execution");
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("Admin to Add: ", adminToAdd);
            console2.log("Role: ADMIN_ROLE");

            // Print Gnosis Safe transaction info for grantRole
            bytes memory grantRoleCallData =
                abi.encodeWithSignature("grantRole(bytes32,address)", adminRole, adminToAdd);
            console2.log("================================");
            console2.log("=== GNOSIS SAFE GRANT ROLE INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(adminRole);
            console2.log("Account: ", adminToAdd);
            console2.log("Calldata:");
            console2.logBytes(grantRoleCallData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)");
            console2.log("   - role: ADMIN_ROLE");
            console2.log("   - account: ", adminToAdd);
            console2.log("   - sender: <Safe address>");
            console2.log("");
            console2.log("Expected Event in Raw Hex:");
            console2.log("Event Signature: RoleGranted(bytes32,address,address)");
            // RoleGranted event signature: keccak256("RoleGranted(bytes32,address,address)")
            bytes32 eventSignature = 0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d;
            console2.log("topics[0] (event signature):");
            console2.logBytes32(eventSignature);
            console2.log("topics[1] (role - indexed):");
            console2.logBytes32(adminRole);
            console2.log("topics[2] (account - indexed): 0x000000000000000000000000", adminToAdd);
            console2.log("topics[3] (sender - indexed): <Safe address as bytes32>");
            console2.log("data: 0x (empty - all parameters are indexed)");
            console2.log("=====================================");
            console2.log("ZKC Admin Grant Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            IAccessControl accessControl = IAccessControl(config.zkc);

            // Check if caller has admin role
            require(accessControl.hasRole(zkcContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE");

            // Grant ADMIN_ROLE
            accessControl.grantRole(adminRole, adminToAdd);

            vm.stopBroadcast();

            console2.log("New ZKC Admin: ", adminToAdd);
            console2.log("ADMIN_ROLE granted: ", accessControl.hasRole(adminRole, adminToAdd));
            console2.log("================================================");
            console2.log("ZKC Admin Role Updated Successfully");
        }

        // Update deployment.toml with the new admin (always do this)
        _updateDeploymentConfig(deploymentKey, "zkc-admin-2", adminToAdd);
    }
}

/**
 * Sample Usage for removing admin from ZKC:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_REMOVE="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:RemoveZKCAdmin \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RemoveZKCAdmin is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");

        address adminToRemove = vm.envAddress("ADMIN_TO_REMOVE");
        require(adminToRemove != address(0), "ADMIN_TO_REMOVE environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        ZKC zkcContract = ZKC(config.zkc);
        bytes32 adminRole = zkcContract.ADMIN_ROLE();

        // Safety check: Ensure at least one other admin will remain
        IAccessControl accessControl = IAccessControl(config.zkc);
        address otherAdmin = (adminToRemove == config.zkcAdmin) ? config.zkcAdmin2 : config.zkcAdmin;

        require(
            otherAdmin != address(0) && accessControl.hasRole(adminRole, otherAdmin),
            "Cannot remove admin: would leave ZKC without any admins"
        );

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing revokeRole calldata for Safe execution");
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("Admin to Remove: ", adminToRemove);
            console2.log("Role: ADMIN_ROLE");

            // Print Gnosis Safe transaction info for revokeRole
            bytes memory revokeRoleCallData =
                abi.encodeWithSignature("revokeRole(bytes32,address)", adminRole, adminToRemove);
            console2.log("================================");
            console2.log("=== GNOSIS SAFE REVOKE ROLE INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: revokeRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(adminRole);
            console2.log("Account: ", adminToRemove);
            console2.log("Calldata:");
            console2.logBytes(revokeRoleCallData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender)");
            console2.log("   - role: ADMIN_ROLE");
            console2.log("   - account: ", adminToRemove);
            console2.log("   - sender: <Safe address>");
            console2.log("");
            console2.log("Expected Event in Raw Hex:");
            console2.log("Event Signature: RoleRevoked(bytes32,address,address)");
            // RoleRevoked event signature: keccak256("RoleRevoked(bytes32,address,address)")
            bytes32 eventSignature = 0xf6391f5c32d9c69d2a47ea670b442974b53935d1edc7fd64eb21e047a839171b;
            console2.log("topics[0] (event signature):");
            console2.logBytes32(eventSignature);
            console2.log("topics[1] (role - indexed):");
            console2.logBytes32(adminRole);
            console2.log("topics[2] (account - indexed): 0x000000000000000000000000", adminToRemove);
            console2.log("topics[3] (sender - indexed): <Safe address as bytes32>");
            console2.log("data: 0x (empty - all parameters are indexed)");
            console2.log("=====================================");
            console2.log("ZKC Admin Revoke Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            // Check if caller has admin role
            require(accessControl.hasRole(zkcContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE");

            // Revoke ADMIN_ROLE
            accessControl.revokeRole(adminRole, adminToRemove);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("Removed ZKC Admin: ", adminToRemove);
            console2.log("Other Admin still active: ", otherAdmin);
            console2.log("ADMIN_ROLE revoked: ", !accessControl.hasRole(adminRole, adminToRemove));
            console2.log("================================================");
            console2.log("ZKC Admin Role Removed Successfully");
        }

        // Remove from deployment.toml - check both admin fields
        _removeAdminFromToml(deploymentKey, adminToRemove, "zkc-admin", "zkc-admin-2");
    }
}

/**
 * Sample Usage for adding admin to veZKC:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_ADD="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:AddVeZKCAdmin \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract AddVeZKCAdmin is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.veZKC != address(0), "veZKC address not set in deployment.toml");

        address adminToAdd = vm.envAddress("ADMIN_TO_ADD");
        require(adminToAdd != address(0), "ADMIN_TO_ADD environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        veZKC veZKCContract = veZKC(config.veZKC);
        bytes32 adminRole = veZKCContract.ADMIN_ROLE();

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing grantRole calldata for Safe execution");
            console2.log("veZKC Contract: ", config.veZKC);
            console2.log("Admin to Add: ", adminToAdd);
            console2.log("Role: ADMIN_ROLE");

            // Print Gnosis Safe transaction info for grantRole
            bytes memory grantRoleCallData =
                abi.encodeWithSignature("grantRole(bytes32,address)", adminRole, adminToAdd);
            console2.log("================================");
            console2.log("=== GNOSIS SAFE GRANT ROLE INFO ===");
            console2.log("Target Address (To): ", config.veZKC);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(adminRole);
            console2.log("Account: ", adminToAdd);
            console2.log("Calldata:");
            console2.logBytes(grantRoleCallData);
            console2.log("=====================================");
            console2.log("veZKC Admin Grant Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            IAccessControl accessControl = IAccessControl(config.veZKC);

            // Check if caller has admin role
            require(accessControl.hasRole(veZKCContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE");

            // Grant ADMIN_ROLE
            accessControl.grantRole(adminRole, adminToAdd);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("veZKC Contract: ", config.veZKC);
            console2.log("New veZKC Admin: ", adminToAdd);
            console2.log("ADMIN_ROLE granted: ", accessControl.hasRole(adminRole, adminToAdd));
            console2.log("================================================");
            console2.log("veZKC Admin Role Updated Successfully");
        }

        // Update deployment.toml with the new admin (always do this)
        if (config.veZKCAdmin2 == address(0) || config.veZKCAdmin2 == adminToAdd) {
            _updateDeploymentConfig(deploymentKey, "vezkc-admin-2", adminToAdd);
        } else if (config.veZKCAdmin == address(0) || config.veZKCAdmin == adminToAdd) {
            _updateDeploymentConfig(deploymentKey, "vezkc-admin", adminToAdd);
        } else {
            revert("veZKCAdmin2 and veZKCAdmin are both set already");
        }
    }
}

/**
 * Sample Usage for removing admin from veZKC:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_REMOVE="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:RemoveVeZKCAdmin \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RemoveVeZKCAdmin is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.veZKC != address(0), "veZKC address not set in deployment.toml");

        address adminToRemove = vm.envAddress("ADMIN_TO_REMOVE");
        require(adminToRemove != address(0), "ADMIN_TO_REMOVE environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        veZKC veZKCContract = veZKC(config.veZKC);
        bytes32 adminRole = veZKCContract.ADMIN_ROLE();

        // Safety check: Ensure at least one other admin will remain
        IAccessControl accessControl = IAccessControl(config.veZKC);
        address otherAdmin = (config.veZKCAdmin != address(0) && config.veZKCAdmin != adminToRemove)
            ? config.veZKCAdmin
            : config.veZKCAdmin2;
        require(
            otherAdmin != adminToRemove && otherAdmin != address(0)
                && accessControl.hasRole(veZKCContract.ADMIN_ROLE(), otherAdmin),
            "Cannot remove admin: would leave veZKC without any admins"
        );

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing revokeRole calldata for Safe execution");
            console2.log("veZKC Contract: ", config.veZKC);
            console2.log("Admin to Remove: ", adminToRemove);
            console2.log("Other Admin still active: ", otherAdmin);
            console2.log("Role: ADMIN_ROLE");

            // Print Gnosis Safe transaction info for revokeRole
            bytes memory revokeRoleCallData =
                abi.encodeWithSignature("revokeRole(bytes32,address)", adminRole, adminToRemove);
            console2.log("================================");
            console2.log("=== GNOSIS SAFE REVOKE ROLE INFO ===");
            console2.log("Target Address (To): ", config.veZKC);
            console2.log("Function: revokeRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(adminRole);
            console2.log("Account: ", adminToRemove);
            console2.log("Calldata:");
            console2.logBytes(revokeRoleCallData);
            console2.log("=====================================");
            console2.log("veZKC Admin Revoke Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            // Check if caller has admin role
            require(accessControl.hasRole(veZKCContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE");

            // Revoke ADMIN_ROLE
            accessControl.revokeRole(adminRole, adminToRemove);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("veZKC Contract: ", config.veZKC);
            console2.log("Removed veZKC Admin: ", adminToRemove);
            console2.log("Other Admin still active: ", otherAdmin);
            console2.log("ADMIN_ROLE revoked: ", !accessControl.hasRole(adminRole, adminToRemove));
            console2.log("================================================");
            console2.log("veZKC Admin Role Removed Successfully");
        }

        // Remove from deployment.toml - check both admin fields
        _removeAdminFromToml(deploymentKey, adminToRemove, "vezkc-admin", "vezkc-admin-2");
    }
}

/**
 * Sample Usage for adding admin to StakingRewards:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_ADD="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:AddStakingRewardsAdmin \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract AddStakingRewardsAdmin is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.stakingRewards != address(0), "StakingRewards address not set in deployment.toml");

        address adminToAdd = vm.envAddress("ADMIN_TO_ADD");
        require(adminToAdd != address(0), "ADMIN_TO_ADD environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        StakingRewards stakingRewardsContract = StakingRewards(config.stakingRewards);
        bytes32 adminRole = stakingRewardsContract.ADMIN_ROLE();

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing grantRole calldata for Safe execution");
            console2.log("StakingRewards Contract: ", config.stakingRewards);
            console2.log("Admin to Add: ", adminToAdd);
            console2.log("Role: ADMIN_ROLE");

            // Print Gnosis Safe transaction info for grantRole
            bytes memory grantRoleCallData =
                abi.encodeWithSignature("grantRole(bytes32,address)", adminRole, adminToAdd);
            console2.log("================================");
            console2.log("=== GNOSIS SAFE GRANT ROLE INFO ===");
            console2.log("Target Address (To): ", config.stakingRewards);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(adminRole);
            console2.log("Account: ", adminToAdd);
            console2.log("Calldata:");
            console2.logBytes(grantRoleCallData);
            console2.log("=====================================");
            console2.log("StakingRewards Admin Grant Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            IAccessControl accessControl = IAccessControl(config.stakingRewards);

            // Check if caller has admin role
            require(
                accessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE"
            );

            // Grant ADMIN_ROLE
            accessControl.grantRole(adminRole, adminToAdd);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("StakingRewards Contract: ", config.stakingRewards);
            console2.log("New StakingRewards Admin: ", adminToAdd);
            console2.log("ADMIN_ROLE granted: ", accessControl.hasRole(adminRole, adminToAdd));
            console2.log("================================================");
            console2.log("StakingRewards Admin Role Updated Successfully");
        }

        // Update deployment.toml with the new admin (always do this)
        if (config.stakingRewardsAdmin2 == address(0) || config.stakingRewardsAdmin2 == adminToAdd) {
            _updateDeploymentConfig(deploymentKey, "staking-rewards-admin-2", adminToAdd);
        } else if (config.stakingRewardsAdmin == address(0) || config.stakingRewardsAdmin == adminToAdd) {
            _updateDeploymentConfig(deploymentKey, "staking-rewards-admin", adminToAdd);
        } else {
            revert("staking-rewards-admin-2 and staking-rewards-admin are both set already");
        }
    }
}

/**
 * Sample Usage for removing admin from StakingRewards:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_REMOVE="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:RemoveStakingRewardsAdmin \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RemoveStakingRewardsAdmin is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.stakingRewards != address(0), "StakingRewards address not set in deployment.toml");

        address adminToRemove = vm.envAddress("ADMIN_TO_REMOVE");
        require(adminToRemove != address(0), "ADMIN_TO_REMOVE environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        StakingRewards stakingRewardsContract = StakingRewards(config.stakingRewards);
        bytes32 adminRole = stakingRewardsContract.ADMIN_ROLE();

        // Safety check: Ensure at least one other admin will remain
        IAccessControl accessControl = IAccessControl(config.stakingRewards);

        address otherAdmin = (config.stakingRewardsAdmin != address(0) && config.stakingRewardsAdmin != adminToRemove)
            ? config.stakingRewardsAdmin
            : config.stakingRewardsAdmin2;
        require(
            otherAdmin != adminToRemove && otherAdmin != address(0)
                && accessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), otherAdmin),
            "Cannot remove admin: would leave StakingRewards without any admins"
        );

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing revokeRole calldata for Safe execution");
            console2.log("StakingRewards Contract: ", config.stakingRewards);
            console2.log("Admin to Remove: ", adminToRemove);
            console2.log("Other Admin still active: ", otherAdmin);
            console2.log("Role: ADMIN_ROLE");

            // Print Gnosis Safe transaction info for revokeRole
            bytes memory revokeRoleCallData =
                abi.encodeWithSignature("revokeRole(bytes32,address)", adminRole, adminToRemove);
            console2.log("================================");
            console2.log("=== GNOSIS SAFE REVOKE ROLE INFO ===");
            console2.log("Target Address (To): ", config.stakingRewards);
            console2.log("Function: revokeRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(adminRole);
            console2.log("Account: ", adminToRemove);
            console2.log("Calldata:");
            console2.logBytes(revokeRoleCallData);
            console2.log("=====================================");
            console2.log("StakingRewards Admin Revoke Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            // Check if caller has admin role
            require(
                accessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE"
            );

            // Revoke ADMIN_ROLE
            accessControl.revokeRole(adminRole, adminToRemove);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("StakingRewards Contract: ", config.stakingRewards);
            console2.log("Removed StakingRewards Admin: ", adminToRemove);
            console2.log("Other Admin still active: ", otherAdmin);
            console2.log("ADMIN_ROLE revoked: ", !accessControl.hasRole(adminRole, adminToRemove));
            console2.log("================================================");
            console2.log("StakingRewards Admin Role Removed Successfully");
        }

        // Remove from deployment.toml - check both admin fields
        _removeAdminFromToml(deploymentKey, adminToRemove, "staking-rewards-admin", "staking-rewards-admin-2");
    }
}

/**
 * Sample Usage for adding admin to SupplyCalculator:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_ADD="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:AddSupplyCalculatorAdmin \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract AddSupplyCalculatorAdmin is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.supplyCalculator != address(0), "SupplyCalculator address not set in deployment.toml");

        address adminToAdd = vm.envAddress("ADMIN_TO_ADD");
        require(adminToAdd != address(0), "ADMIN_TO_ADD environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        SupplyCalculator supplyCalculatorContract = SupplyCalculator(config.supplyCalculator);
        bytes32 adminRole = supplyCalculatorContract.ADMIN_ROLE();

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing grantRole calldata for Safe execution");
            console2.log("SupplyCalculator Contract: ", config.supplyCalculator);
            console2.log("Admin to Add: ", adminToAdd);
            console2.log("Role: ADMIN_ROLE");

            // Print Gnosis Safe transaction info for grantRole
            bytes memory grantRoleCallData =
                abi.encodeWithSignature("grantRole(bytes32,address)", adminRole, adminToAdd);
            console2.log("================================");
            console2.log("=== GNOSIS SAFE GRANT ROLE INFO ===");
            console2.log("Target Address (To): ", config.supplyCalculator);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(adminRole);
            console2.log("Account: ", adminToAdd);
            console2.log("Calldata:");
            console2.logBytes(grantRoleCallData);
            console2.log("=====================================");
            console2.log("SupplyCalculator Admin Grant Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            IAccessControl accessControl = IAccessControl(config.supplyCalculator);

            // Check if caller has admin role
            require(
                accessControl.hasRole(supplyCalculatorContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE"
            );

            // Grant ADMIN_ROLE
            accessControl.grantRole(adminRole, adminToAdd);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("SupplyCalculator Contract: ", config.supplyCalculator);
            console2.log("New SupplyCalculator Admin: ", adminToAdd);
            console2.log("ADMIN_ROLE granted: ", accessControl.hasRole(adminRole, adminToAdd));
            console2.log("================================================");
            console2.log("SupplyCalculator Admin Role Updated Successfully");
        }

        // Update deployment.toml with the new admin (always do this)
        if (config.supplyCalculatorAdmin2 == address(0) || config.supplyCalculatorAdmin2 == adminToAdd) {
            _updateDeploymentConfig(deploymentKey, "supply-calculator-admin-2", adminToAdd);
        } else if (config.supplyCalculatorAdmin == address(0) || config.supplyCalculatorAdmin == adminToAdd) {
            _updateDeploymentConfig(deploymentKey, "supply-calculator-admin", adminToAdd);
        } else {
            revert("supply-calculator-admin-2 and supply-calculator-admin are both set already");
        }
    }
}

/**
 * Sample Usage for removing admin from SupplyCalculator:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_REMOVE="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:RemoveSupplyCalculatorAdmin \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RemoveSupplyCalculatorAdmin is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.supplyCalculator != address(0), "SupplyCalculator address not set in deployment.toml");

        address adminToRemove = vm.envAddress("ADMIN_TO_REMOVE");
        require(adminToRemove != address(0), "ADMIN_TO_REMOVE environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        SupplyCalculator supplyCalculatorContract = SupplyCalculator(config.supplyCalculator);
        bytes32 adminRole = supplyCalculatorContract.ADMIN_ROLE();

        // Safety check: Ensure at least one other admin will remain
        IAccessControl accessControl = IAccessControl(config.supplyCalculator);

        address otherAdmin = (config.supplyCalculatorAdmin != address(0)
                && config.supplyCalculatorAdmin != adminToRemove)
            ? config.supplyCalculatorAdmin
            : config.supplyCalculatorAdmin2;
        require(
            otherAdmin != adminToRemove && otherAdmin != address(0)
                && accessControl.hasRole(supplyCalculatorContract.ADMIN_ROLE(), otherAdmin),
            "Cannot remove admin: would leave SupplyCalculator without any admins"
        );

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing revokeRole calldata for Safe execution");
            console2.log("SupplyCalculator Contract: ", config.supplyCalculator);
            console2.log("Admin to Remove: ", adminToRemove);
            console2.log("Other Admin still active: ", otherAdmin);
            console2.log("Role: ADMIN_ROLE");

            // Print Gnosis Safe transaction info for revokeRole
            bytes memory revokeRoleCallData =
                abi.encodeWithSignature("revokeRole(bytes32,address)", adminRole, adminToRemove);
            console2.log("================================");
            console2.log("=== GNOSIS SAFE REVOKE ROLE INFO ===");
            console2.log("Target Address (To): ", config.supplyCalculator);
            console2.log("Function: revokeRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(adminRole);
            console2.log("Account: ", adminToRemove);
            console2.log("Calldata:");
            console2.logBytes(revokeRoleCallData);
            console2.log("=====================================");
            console2.log("SupplyCalculator Admin Revoke Role Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            // Check if caller has admin role
            require(
                accessControl.hasRole(supplyCalculatorContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE"
            );

            // Revoke ADMIN_ROLE
            accessControl.revokeRole(adminRole, adminToRemove);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("SupplyCalculator Contract: ", config.supplyCalculator);
            console2.log("Removed SupplyCalculator Admin: ", adminToRemove);
            console2.log("Other Admin still active: ", otherAdmin);
            console2.log("ADMIN_ROLE revoked: ", !accessControl.hasRole(adminRole, adminToRemove));
            console2.log("================================================");
            console2.log("SupplyCalculator Admin Role Removed Successfully");
        }

        // Remove from deployment.toml - check both admin fields
        _removeAdminFromToml(deploymentKey, adminToRemove, "supply-calculator-admin", "supply-calculator-admin-2");
    }
}

/**
 * Sample Usage for adding admin to all contracts:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_ADD="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:AddAdminAll \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract AddAdminAll is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");
        require(config.veZKC != address(0), "veZKC address not set in deployment.toml");
        require(config.stakingRewards != address(0), "StakingRewards address not set in deployment.toml");

        address adminToAdd = vm.envAddress("ADMIN_TO_ADD");
        require(adminToAdd != address(0), "ADMIN_TO_ADD environment variable not set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing grantRole calldata for Safe execution");
            console2.log("Admin to Add: ", adminToAdd);
            console2.log("");

            // ZKC
            ZKC zkcContract = ZKC(config.zkc);
            bytes32 zkcAdminRole = zkcContract.ADMIN_ROLE();
            bytes memory zkcGrantRoleCallData =
                abi.encodeWithSignature("grantRole(bytes32,address)", zkcAdminRole, adminToAdd);

            console2.log("=== ZKC ADMIN GRANT ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(zkcAdminRole);
            console2.log("Account: ", adminToAdd);
            console2.log("Calldata:");
            console2.logBytes(zkcGrantRoleCallData);
            console2.log("");

            // veZKC
            veZKC veZKCContract = veZKC(config.veZKC);
            bytes32 veZKCAdminRole = veZKCContract.ADMIN_ROLE();
            bytes memory veZKCGrantRoleCallData =
                abi.encodeWithSignature("grantRole(bytes32,address)", veZKCAdminRole, adminToAdd);

            console2.log("=== veZKC ADMIN GRANT ===");
            console2.log("Target Address (To): ", config.veZKC);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(veZKCAdminRole);
            console2.log("Account: ", adminToAdd);
            console2.log("Calldata:");
            console2.logBytes(veZKCGrantRoleCallData);
            console2.log("");

            // StakingRewards
            StakingRewards stakingRewardsContract = StakingRewards(config.stakingRewards);
            bytes32 stakingAdminRole = stakingRewardsContract.ADMIN_ROLE();
            bytes memory stakingGrantRoleCallData =
                abi.encodeWithSignature("grantRole(bytes32,address)", stakingAdminRole, adminToAdd);

            console2.log("=== StakingRewards ADMIN GRANT ===");
            console2.log("Target Address (To): ", config.stakingRewards);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(stakingAdminRole);
            console2.log("Account: ", adminToAdd);
            console2.log("Calldata:");
            console2.logBytes(stakingGrantRoleCallData);
            console2.log("");

            console2.log("Expected Events for Each Contract:");
            console2.log("RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)");
            console2.log("   - role: ADMIN_ROLE (0x00... for all contracts)");
            console2.log("   - account: ", adminToAdd);
            console2.log("   - sender: <Safe address>");
            console2.log("=====================================");
            console2.log("All Admin Grant Role Calldata Ready");
            console2.log("Execute 3 transactions in Gnosis Safe with the above calldata");
        } else {
            vm.startBroadcast();

            // Grant admin role to all three contracts
            ZKC zkcContract = ZKC(config.zkc);
            veZKC veZKCContract = veZKC(config.veZKC);
            StakingRewards stakingRewardsContract = StakingRewards(config.stakingRewards);

            IAccessControl zkcAccessControl = IAccessControl(config.zkc);
            IAccessControl veZKCAccessControl = IAccessControl(config.veZKC);
            IAccessControl stakingAccessControl = IAccessControl(config.stakingRewards);

            // Check if caller has admin role on all contracts
            require(zkcAccessControl.hasRole(zkcContract.ADMIN_ROLE(), msg.sender), "Caller must have ZKC ADMIN_ROLE");
            require(
                veZKCAccessControl.hasRole(veZKCContract.ADMIN_ROLE(), msg.sender), "Caller must have veZKC ADMIN_ROLE"
            );
            require(
                stakingAccessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), msg.sender),
                "Caller must have StakingRewards ADMIN_ROLE"
            );

            // Grant roles
            zkcAccessControl.grantRole(zkcContract.ADMIN_ROLE(), adminToAdd);
            veZKCAccessControl.grantRole(veZKCContract.ADMIN_ROLE(), adminToAdd);
            stakingAccessControl.grantRole(stakingRewardsContract.ADMIN_ROLE(), adminToAdd);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("veZKC Contract: ", config.veZKC);
            console2.log("StakingRewards Contract: ", config.stakingRewards);
            console2.log("New Admin: ", adminToAdd);
            console2.log("ZKC ADMIN_ROLE granted: ", zkcAccessControl.hasRole(zkcContract.ADMIN_ROLE(), adminToAdd));
            console2.log(
                "veZKC ADMIN_ROLE granted: ", veZKCAccessControl.hasRole(veZKCContract.ADMIN_ROLE(), adminToAdd)
            );
            console2.log(
                "StakingRewards ADMIN_ROLE granted: ",
                stakingAccessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), adminToAdd)
            );
            console2.log("================================================");
            console2.log("All Admin Roles Updated Successfully");
        }

        // Update deployment.toml with the new admin (always do this)
        _updateDeploymentConfig(deploymentKey, "zkc-admin-2", adminToAdd);
        _updateDeploymentConfig(deploymentKey, "vezkc-admin-2", adminToAdd);
        _updateDeploymentConfig(deploymentKey, "staking-rewards-admin-2", adminToAdd);
    }
}

/**
 * Sample Usage for removing admin from all contracts:
 *
 * export CHAIN_KEY="anvil"
 * export ADMIN_TO_REMOVE="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 *
 * forge script script/Update.s.sol:RemoveAdminAll \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RemoveAdminAll is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");
        require(config.veZKC != address(0), "veZKC address not set in deployment.toml");
        require(config.stakingRewards != address(0), "StakingRewards address not set in deployment.toml");

        address adminToRemove = vm.envAddress("ADMIN_TO_REMOVE");
        require(adminToRemove != address(0), "ADMIN_TO_REMOVE environment variable not set");

        // Safety check: Ensure at least one other admin will remain on each contract
        ZKC zkcContract = ZKC(config.zkc);
        veZKC veZKCContract = veZKC(config.veZKC);
        StakingRewards stakingRewardsContract = StakingRewards(config.stakingRewards);

        IAccessControl zkcAccessControl = IAccessControl(config.zkc);
        IAccessControl veZKCAccessControl = IAccessControl(config.veZKC);
        IAccessControl stakingAccessControl = IAccessControl(config.stakingRewards);

        // Check ZKC contract
        address zkcOtherAdmin =
            (config.zkcAdmin != address(0) && config.zkcAdmin != adminToRemove) ? config.zkcAdmin : config.zkcAdmin2;
        assert(zkcOtherAdmin != adminToRemove && zkcOtherAdmin != address(0));
        require(
            zkcOtherAdmin != address(0) && zkcAccessControl.hasRole(zkcContract.ADMIN_ROLE(), zkcOtherAdmin),
            "Cannot remove admin: would leave ZKC without any admins"
        );

        // Check veZKC contract
        address veZKCOtherAdmin = (config.veZKCAdmin != address(0) && config.veZKCAdmin != adminToRemove)
            ? config.veZKCAdmin
            : config.veZKCAdmin2;
        assert(veZKCOtherAdmin != adminToRemove && veZKCOtherAdmin != address(0));
        require(
            veZKCOtherAdmin != address(0) && veZKCAccessControl.hasRole(veZKCContract.ADMIN_ROLE(), veZKCOtherAdmin),
            "Cannot remove admin: would leave veZKC without any admins"
        );

        // Check StakingRewards contract
        address stakingOtherAdmin = (config.stakingRewardsAdmin != address(0)
                && config.stakingRewardsAdmin != adminToRemove)
            ? config.stakingRewardsAdmin
            : config.stakingRewardsAdmin2;
        assert(stakingOtherAdmin != adminToRemove && stakingOtherAdmin != address(0));
        require(
            stakingOtherAdmin != address(0)
                && stakingAccessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), stakingOtherAdmin),
            "Cannot remove admin: would leave StakingRewards without any admins"
        );

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing revokeRole calldata for Safe execution");
            console2.log("Admin to Remove: ", adminToRemove);
            console2.log("");

            // ZKC
            ZKC zkcContract = ZKC(config.zkc);
            bytes32 zkcAdminRole = zkcContract.ADMIN_ROLE();
            bytes memory zkcRevokeRoleCallData =
                abi.encodeWithSignature("revokeRole(bytes32,address)", zkcAdminRole, adminToRemove);

            console2.log("=== ZKC ADMIN REVOKE ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: revokeRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(zkcAdminRole);
            console2.log("Account: ", adminToRemove);
            console2.log("Calldata:");
            console2.logBytes(zkcRevokeRoleCallData);
            console2.log("");

            // veZKC
            veZKC veZKCContract = veZKC(config.veZKC);
            bytes32 veZKCAdminRole = veZKCContract.ADMIN_ROLE();
            bytes memory veZKCRevokeRoleCallData =
                abi.encodeWithSignature("revokeRole(bytes32,address)", veZKCAdminRole, adminToRemove);

            console2.log("=== veZKC ADMIN REVOKE ===");
            console2.log("Target Address (To): ", config.veZKC);
            console2.log("Function: revokeRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(veZKCAdminRole);
            console2.log("Account: ", adminToRemove);
            console2.log("Calldata:");
            console2.logBytes(veZKCRevokeRoleCallData);
            console2.log("");

            // StakingRewards
            StakingRewards stakingRewardsContract = StakingRewards(config.stakingRewards);
            bytes32 stakingAdminRole = stakingRewardsContract.ADMIN_ROLE();
            bytes memory stakingRevokeRoleCallData =
                abi.encodeWithSignature("revokeRole(bytes32,address)", stakingAdminRole, adminToRemove);

            console2.log("=== StakingRewards ADMIN REVOKE ===");
            console2.log("Target Address (To): ", config.stakingRewards);
            console2.log("Function: revokeRole(bytes32,address)");
            console2.log("Role: ");
            console2.logBytes32(stakingAdminRole);
            console2.log("Account: ", adminToRemove);
            console2.log("Calldata:");
            console2.logBytes(stakingRevokeRoleCallData);
            console2.log("");

            console2.log("Expected Events for Each Contract:");
            console2.log("RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender)");
            console2.log("   - role: ADMIN_ROLE (0x00... for all contracts)");
            console2.log("   - account: ", adminToRemove);
            console2.log("   - sender: <Safe address>");
            console2.log("=====================================");
            console2.log("All Admin Revoke Role Calldata Ready");
            console2.log("Execute 3 transactions in Gnosis Safe with the above calldata");
        } else {
            vm.startBroadcast();

            // Check if caller has admin role on all contracts
            require(zkcAccessControl.hasRole(zkcContract.ADMIN_ROLE(), msg.sender), "Caller must have ZKC ADMIN_ROLE");
            require(
                veZKCAccessControl.hasRole(veZKCContract.ADMIN_ROLE(), msg.sender), "Caller must have veZKC ADMIN_ROLE"
            );
            require(
                stakingAccessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), msg.sender),
                "Caller must have StakingRewards ADMIN_ROLE"
            );

            // Revoke roles
            zkcAccessControl.revokeRole(zkcContract.ADMIN_ROLE(), adminToRemove);
            veZKCAccessControl.revokeRole(veZKCContract.ADMIN_ROLE(), adminToRemove);
            stakingAccessControl.revokeRole(stakingRewardsContract.ADMIN_ROLE(), adminToRemove);

            vm.stopBroadcast();

            // Sanity checks
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("veZKC Contract: ", config.veZKC);
            console2.log("StakingRewards Contract: ", config.stakingRewards);
            console2.log("Removed Admin: ", adminToRemove);
            console2.log("ZKC ADMIN_ROLE revoked: ", !zkcAccessControl.hasRole(zkcContract.ADMIN_ROLE(), adminToRemove));
            console2.log(
                "veZKC ADMIN_ROLE revoked: ", !veZKCAccessControl.hasRole(veZKCContract.ADMIN_ROLE(), adminToRemove)
            );
            console2.log(
                "StakingRewards ADMIN_ROLE revoked: ",
                !stakingAccessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), adminToRemove)
            );
            console2.log("================================================");
            console2.log("All Admin Roles Removed Successfully");
        }

        // Remove from deployment.toml - check both admin fields for all contracts
        _removeAdminFromToml(deploymentKey, adminToRemove, "zkc-admin", "zkc-admin-2");
        _removeAdminFromToml(deploymentKey, adminToRemove, "vezkc-admin", "vezkc-admin-2");
        _removeAdminFromToml(deploymentKey, adminToRemove, "staking-rewards-admin", "staking-rewards-admin-2");
    }
}
