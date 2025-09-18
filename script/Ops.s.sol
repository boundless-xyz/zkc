// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import {ConfigLoader, DeploymentConfig} from "./Config.s.sol";
import {BaseDeployment} from "./BaseDeployment.s.sol";
import {ZKC} from "../src/ZKC.sol";

/**
 * Development script to mint initial ZKC tokens to the caller
 *
 * Sample Usage:
 *
 * export CHAIN_KEY="anvil"
 * export MINT_AMOUNT="1000000000000000000000000"  # 1M ZKC (with 18 decimals)
 *
 * forge script script/Ops.s.sol:Dev_InitialMintToSelf \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 *
 * Note: This script requires the caller to be one of the initial minters (initialMinter1 or initialMinter2)
 */
contract Dev_InitialMintToSelf is BaseDeployment {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");

        uint256 mintAmount = vm.envUint("MINT_AMOUNT");
        require(mintAmount > 0, "MINT_AMOUNT environment variable must be greater than 0");

        ZKC zkcContract = ZKC(config.zkc);

        // Get caller address
        address caller = msg.sender;

        // Check if caller is an initial minter
        address initialMinter1 = zkcContract.initialMinter1();
        address initialMinter2 = zkcContract.initialMinter2();

        require(caller == initialMinter1 || caller == initialMinter2, "Caller must be initialMinter1 or initialMinter2");

        // Get remaining amounts before minting
        uint256 minter1Remaining = zkcContract.initialMinter1Remaining();
        uint256 minter2Remaining = zkcContract.initialMinter2Remaining();

        // Check if caller has enough remaining allocation
        if (caller == initialMinter1) {
            require(mintAmount <= minter1Remaining, "Not enough remaining allocation for initialMinter1");
        } else {
            require(mintAmount <= minter2Remaining, "Not enough remaining allocation for initialMinter2");
        }

        // Prepare arrays for initialMint call
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = caller;
        amounts[0] = mintAmount;

        // Perform initial mint
        zkcContract.initialMint(recipients, amounts);

        vm.stopBroadcast();

        // Sanity checks and logging
        uint256 callerBalance = zkcContract.balanceOf(caller);
        console2.log("ZKC Contract: ", config.zkc);
        console2.log("Caller: ", caller);
        console2.log("Mint Amount: ", mintAmount);
        console2.log("Mint Amount (in ZKC): ", mintAmount / 10 ** 18);
        console2.log("Caller Balance After: ", callerBalance);
        console2.log("Caller Balance After (in ZKC): ", callerBalance / 10 ** 18);

        if (caller == initialMinter1) {
            uint256 newRemaining = zkcContract.initialMinter1Remaining();
            console2.log("InitialMinter1 Remaining Before: ", minter1Remaining / 10 ** 18, "ZKC");
            console2.log("InitialMinter1 Remaining After: ", newRemaining / 10 ** 18, "ZKC");
        } else {
            uint256 newRemaining = zkcContract.initialMinter2Remaining();
            console2.log("InitialMinter2 Remaining Before: ", minter2Remaining / 10 ** 18, "ZKC");
            console2.log("InitialMinter2 Remaining After: ", newRemaining / 10 ** 18, "ZKC");
        }

        console2.log("================================================");
        console2.log("Initial Mint to Self Completed Successfully");
    }
}

/**
 * Script to grant POVW_MINTER_ROLE in ZKC contract
 *
 * Sample Usage:
 *
 * export CHAIN_KEY="anvil"
 * export POVW_MINTER="0x1234567890123456789012345678901234567890"
 *
 * forge script script/Ops.s.sol:UpdatePOVWMinter \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 *
 * For Gnosis Safe (generate calldata only):
 * export GNOSIS_EXECUTE=true
 * forge script script/Ops.s.sol:UpdatePOVWMinter \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpdatePOVWMinter is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");

        address povwMinter = vm.envAddress("POVW_MINTER");
        require(povwMinter != address(0), "POVW_MINTER environment variable must be set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);

        ZKC zkcContract = ZKC(config.zkc);
        bytes32 povwMinterRole = zkcContract.POVW_MINTER_ROLE();

        if (gnosisExecute) {
            // Print Gnosis Safe transaction info for manual execution
            console2.log("================================");
            console2.log("================================");
            console2.log("=== GNOSIS SAFE TRANSACTION INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: POVW_MINTER_ROLE");
            console2.log("Account: ", povwMinter);

            bytes memory callData = abi.encodeWithSignature("grantRole(bytes32,address)", povwMinterRole, povwMinter);
            console2.log("");
            console2.log("Calldata:");
            console2.logBytes(callData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. RoleGranted(bytes32 role, address account, address sender)");
            console2.log("   - role: ", vm.toString(povwMinterRole));
            console2.log("   - account: ", povwMinter);
            console2.log("================================");
        } else {
            vm.startBroadcast();

            // Grant POVW_MINTER_ROLE to the specified address
            zkcContract.grantRole(povwMinterRole, povwMinter);

            vm.stopBroadcast();

            // Update deployment.toml with the new POVW minter
            _updateDeploymentConfig(deploymentKey, "povw-minter", povwMinter);

            // Verification
            bool hasRole = zkcContract.hasRole(povwMinterRole, povwMinter);
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("POVW Minter Address: ", povwMinter);
            console2.log("Role Granted: ", hasRole);
            console2.log("================================================");
            console2.log("POVW Minter Role Updated Successfully");
        }
    }
}

/**
 * Script to grant STAKING_MINTER_ROLE in ZKC contract
 *
 * Sample Usage:
 *
 * export CHAIN_KEY="anvil"
 * export STAKING_MINTER="0x1234567890123456789012345678901234567890"
 *
 * forge script script/Ops.s.sol:UpdateStakingMinter \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 *
 * For Gnosis Safe (generate calldata only):
 * export GNOSIS_EXECUTE=true
 * forge script script/Ops.s.sol:UpdateStakingMinter \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpdateStakingMinter is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");

        address stakingMinter = vm.envAddress("STAKING_MINTER");
        require(stakingMinter != address(0), "STAKING_MINTER environment variable must be set");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);

        ZKC zkcContract = ZKC(config.zkc);
        bytes32 stakingMinterRole = zkcContract.STAKING_MINTER_ROLE();

        if (gnosisExecute) {
            // Print Gnosis Safe transaction info for manual execution
            console2.log("================================");
            console2.log("================================");
            console2.log("=== GNOSIS SAFE TRANSACTION INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: grantRole(bytes32,address)");
            console2.log("Role: STAKING_MINTER_ROLE");
            console2.log("Account: ", stakingMinter);

            bytes memory callData = abi.encodeWithSignature("grantRole(bytes32,address)", stakingMinterRole, stakingMinter);
            console2.log("");
            console2.log("Calldata:");
            console2.logBytes(callData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. RoleGranted(bytes32 role, address account, address sender)");
            console2.log("   - role: ", vm.toString(stakingMinterRole));
            console2.log("   - account: ", stakingMinter);
            console2.log("================================");
        } else {
            vm.startBroadcast();

            // Grant STAKING_MINTER_ROLE to the specified address
            zkcContract.grantRole(stakingMinterRole, stakingMinter);

            vm.stopBroadcast();

            // Update deployment.toml with the new staking minter
            _updateDeploymentConfig(deploymentKey, "staking-minter", stakingMinter);

            // Verification
            bool hasRole = zkcContract.hasRole(stakingMinterRole, stakingMinter);
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("Staking Minter Address: ", stakingMinter);
            console2.log("Role Granted: ", hasRole);
            console2.log("================================================");
            console2.log("Staking Minter Role Updated Successfully");
        }
    }
}
