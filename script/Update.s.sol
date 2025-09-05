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
        vm.startBroadcast();

        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");

        address povwMinter = vm.envAddress("POVW_MINTER");
        require(povwMinter != address(0), "POVW_MINTER environment variable not set");

        ZKC zkcContract = ZKC(config.zkc);
        IAccessControl accessControl = IAccessControl(config.zkc);

        // Check if caller has admin role
        require(accessControl.hasRole(zkcContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE");

        // Grant POVW_MINTER_ROLE
        bytes32 povwMinterRole = zkcContract.POVW_MINTER_ROLE();
        accessControl.grantRole(povwMinterRole, povwMinter);

        vm.stopBroadcast();

        // Update deployment.toml with the new minter
        _updateDeploymentConfig(deploymentKey, "povw-minter", povwMinter);

        // Sanity checks
        console2.log("ZKC Contract: ", config.zkc);
        console2.log("POVW Minter: ", povwMinter);
        console2.log("POVW_MINTER_ROLE granted: ", accessControl.hasRole(povwMinterRole, povwMinter));
        console2.log("================================================");
        console2.log("POVW Minter Role Updated Successfully");
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
        vm.startBroadcast();

        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");

        address stakingMinter = vm.envAddress("STAKING_MINTER");
        require(stakingMinter != address(0), "STAKING_MINTER environment variable not set");

        ZKC zkcContract = ZKC(config.zkc);
        IAccessControl accessControl = IAccessControl(config.zkc);

        // Check if caller has admin role
        require(accessControl.hasRole(zkcContract.ADMIN_ROLE(), msg.sender), "Caller must have ADMIN_ROLE");

        // Grant STAKING_MINTER_ROLE
        bytes32 stakingMinterRole = zkcContract.STAKING_MINTER_ROLE();
        accessControl.grantRole(stakingMinterRole, stakingMinter);

        vm.stopBroadcast();

        // Update deployment.toml with the new minter
        _updateDeploymentConfig(deploymentKey, "staking-minter", stakingMinter);

        // Sanity checks
        console2.log("ZKC Contract: ", config.zkc);
        console2.log("Staking Minter: ", stakingMinter);
        console2.log("STAKING_MINTER_ROLE granted: ", accessControl.hasRole(stakingMinterRole, stakingMinter));
        console2.log("================================================");
        console2.log("Staking Minter Role Updated Successfully");
    }
}