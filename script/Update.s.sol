// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ConfigLoader, DeploymentConfig} from "./Config.s.sol";
import {BaseDeployment} from "./BaseDeployment.s.sol";
import {ZKC} from "../src/ZKC.sol";
import {CirculatingZKC} from "../src/circulating/CirculatingZKC.sol";

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
 * Sample Usage for updating CirculatingZKC unlocked value:
 *
 * # Direct execution:
 * export CHAIN_KEY="anvil"
 * export NEW_UNLOCKED="750000000000000000000000000"  # 750M tokens
 *
 * forge script script/Update.s.sol:UpdateCirculatingUnlocked \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 *
 * # Gnosis Safe execution (print call data only):
 * export CHAIN_KEY="anvil"
 * export NEW_UNLOCKED="750000000000000000000000000"  # 750M tokens
 * export GNOSIS_EXECUTE=true
 *
 * forge script script/Update.s.sol:UpdateCirculatingUnlocked \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpdateCirculatingUnlocked is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.circulatingZKC != address(0), "CirculatingZKC address not set in deployment.toml");

        // Get new unlocked value from environment
        uint256 newUnlocked = vm.envUint("NEW_UNLOCKED");
        require(newUnlocked > 0, "NEW_UNLOCKED must be greater than 0");

        // Check for Gnosis Safe execution mode
        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);

        // Get the contract instance
        CirculatingZKC circulatingContract = CirculatingZKC(config.circulatingZKC);

        // Get current values for logging
        uint256 currentUnlocked = circulatingContract.unlocked();
        uint256 currentCirculatingSupply = circulatingContract.circulatingSupply();

        console2.log("================================================");
        console2.log("Current unlocked amount: ", currentUnlocked);
        console2.log("Current unlocked amount (in tokens): ", currentUnlocked / 10 ** 18);
        console2.log("Current circulating supply: ", currentCirculatingSupply);
        console2.log("Current circulating supply (in tokens): ", currentCirculatingSupply / 10 ** 18);
        console2.log("================================================");

        if (gnosisExecute) {
            // Print Gnosis Safe transaction info for manual execution
            _printGnosisSafeInfo(config.circulatingZKC, newUnlocked);

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
            circulatingContract.updateUnlockedValue(newUnlocked);

            // Get updated values
            uint256 updatedUnlocked = circulatingContract.unlocked();
            uint256 updatedCirculatingSupply = circulatingContract.circulatingSupply();

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
    /// @param targetAddress The CirculatingZKC contract address (target for Gnosis Safe)
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
