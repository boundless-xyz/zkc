// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2} from "forge-std/Script.sol";
import {ZKC} from "../src/ZKC.sol";
import {veZKC} from "../src/veZKC.sol";
import {StakingRewards} from "../src/rewards/StakingRewards.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ConfigLoader, DeploymentConfig} from "./Config.s.sol";
import {BaseDeployment} from "./BaseDeployment.s.sol";

/**
 * Sample Usage (addresses are Anvil default accounts):
 *
 *
 * export ADMIN="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
 * export INITIAL_MINTER_1="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 * export INITIAL_MINTER_2="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
 * export TOTAL_INITIAL_SUPPLY="1000000000000000000000000000"
 * export INITIAL_MINTER_1_AMOUNT="550000000000000000000000000"
 * export INITIAL_MINTER_2_AMOUNT="450000000000000000000000000"
 * export SALT="0x0000000000000000000000000000000000000000000000000000000000000001"
 *
 * forge script script/Deploy.s.sol:DeployZKC \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract DeployZKC is BaseDeployment {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address initialMinter1 = vm.envAddress("INITIAL_MINTER_1");
        address initialMinter2 = vm.envAddress("INITIAL_MINTER_2");
        uint256 totalInitialSupply = vm.envUint("TOTAL_INITIAL_SUPPLY");
        uint256 initialMinter1Amount = vm.envUint("INITIAL_MINTER_1_AMOUNT");
        uint256 initialMinter2Amount = vm.envUint("INITIAL_MINTER_2_AMOUNT");
        require(totalInitialSupply == initialMinter1Amount + initialMinter2Amount);
        bytes32 salt = vm.envBytes32("SALT");
        bytes32 saltImpl = vm.envOr("SALT_IMPL", bytes32(0));
        address admin = vm.envAddress("ADMIN");

        address implementation = address(new ZKC{salt: saltImpl}());
        console2.log("Deployed ZKC implementation to: ", implementation);

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    implementation,
                    abi.encodeCall(
                        ZKC.initialize,
                        (initialMinter1, initialMinter2, initialMinter1Amount, initialMinter2Amount, admin)
                    )
                )
            )
        );
        console2.log("initCodeHash: ");
        console2.logBytes32(initCodeHash);

        // Deploy proxy with CREATE2
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            implementation,
            abi.encodeCall(
                ZKC.initialize, (initialMinter1, initialMinter2, initialMinter1Amount, initialMinter2Amount, admin)
            )
        );
        address zkc = address(proxy);

        (bool success,) = address(proxy).call(abi.encodeCall(ZKC.initializeV2, ()));
        require(success, "initializeV2 call failed");

        vm.stopBroadcast();

        // Update deployment.toml with deployed addresses
        (, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        _updateDeploymentConfig(deploymentKey, "zkc", zkc);
        _updateDeploymentConfig(deploymentKey, "zkc-impl", implementation);
        _updateDeploymentConfig(deploymentKey, "zkc-admin", admin);
        _updateDeploymentConfig(deploymentKey, "zkc-deployer", msg.sender);
        _updateDeploymentCommit(deploymentKey);

        // Sanity checks.
        ZKC zkcContract = ZKC(zkc);
        IAccessControl accessControl = IAccessControl(zkc);
        console2.log("Deployer address: ", msg.sender);
        console2.log("Admin address: ", admin);
        console2.log("Admin role assigned: ", accessControl.hasRole(zkcContract.ADMIN_ROLE(), admin));
        console2.log("Initial Minter 1: ", zkcContract.initialMinter1());
        console2.log("Initial Minter 2: ", zkcContract.initialMinter2());
        console2.log("Initial Minter 1 Amount: ", zkcContract.initialMinter1Remaining());
        console2.log("Initial Minter 1 Amount Value: ", zkcContract.initialMinter1Remaining() / 10 ** 18);
        console2.log("Initial Minter 2 Amount: ", zkcContract.initialMinter2Remaining());
        console2.log("Initial Minter 2 Amount Value: ", zkcContract.initialMinter2Remaining() / 10 ** 18);
        console2.log("================================================");
        console2.log("Deployed ZKC to: ", zkc);
    }

}

/**
 * Sample Usage for veZKC deployment:
 *
 * export CHAIN_KEY="anvil"
 * export SALT="0x0000000000000000000000000000000000000000000000000000000000000001"
 *
 * forge script script/Deploy.s.sol:DeployVeZKC \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract DeployVeZKC is BaseDeployment {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");
        require(config.veZKCAdmin != address(0), "veZKC admin address not set in deployment.toml");

        bytes32 salt = vm.envOr("SALT", bytes32(0));

        // Deploy veZKC implementation
        address veZKCImpl = address(new veZKC{salt: salt}());
        console2.log("Deployed veZKC implementation to: ", veZKCImpl);

        // Deploy proxy with initialization
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            veZKCImpl,
            abi.encodeCall(veZKC.initialize, (config.zkc, config.veZKCAdmin))
        );
        address veZKCAddress = address(proxy);

        vm.stopBroadcast();

        // Update deployment.toml
        _updateDeploymentConfig(deploymentKey, "vezkc", veZKCAddress);
        _updateDeploymentConfig(deploymentKey, "vezkc-impl", veZKCImpl);
        _updateDeploymentConfig(deploymentKey, "vezkc-deployer", msg.sender);
        _updateDeploymentCommit(deploymentKey);

        // Sanity checks
        veZKC veZKCContract = veZKC(veZKCAddress);
        IAccessControl accessControl = IAccessControl(veZKCAddress);
        console2.log("Deployer address: ", msg.sender);
        console2.log("Admin address: ", config.veZKCAdmin);
        console2.log("Admin role assigned: ", accessControl.hasRole(veZKCContract.ADMIN_ROLE(), config.veZKCAdmin));
        console2.log("ZKC token address: ", address(veZKCContract.zkcToken()));
        console2.log("================================================");
        console2.log("Deployed veZKC to: ", veZKCAddress);
    }

}

/**
 * Sample Usage for StakingRewards deployment:
 *
 * export CHAIN_KEY="anvil"
 * export SALT="0x0000000000000000000000000000000000000000000000000000000000000001"
 *
 * forge script script/Deploy.s.sol:DeployStakingRewards \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract DeployStakingRewards is BaseDeployment {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC address not set in deployment.toml");
        require(config.veZKC != address(0), "veZKC address not set in deployment.toml");
        require(config.stakingRewardsAdmin != address(0), "StakingRewards admin address not set in deployment.toml");

        bytes32 salt = vm.envOr("SALT", bytes32(0));

        // Deploy StakingRewards implementation
        address stakingRewardsImpl = address(new StakingRewards{salt: salt}());
        console2.log("Deployed StakingRewards implementation to: ", stakingRewardsImpl);

        // Deploy proxy with initialization
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            stakingRewardsImpl,
            abi.encodeCall(StakingRewards.initialize, (config.zkc, config.veZKC, config.stakingRewardsAdmin))
        );
        address stakingRewardsAddress = address(proxy);

        vm.stopBroadcast();

        // Update deployment.toml
        _updateDeploymentConfig(deploymentKey, "staking-rewards", stakingRewardsAddress);
        _updateDeploymentConfig(deploymentKey, "staking-rewards-impl", stakingRewardsImpl);
        _updateDeploymentConfig(deploymentKey, "staking-rewards-deployer", msg.sender);
        _updateDeploymentCommit(deploymentKey);

        // Sanity checks
        StakingRewards stakingRewardsContract = StakingRewards(stakingRewardsAddress);
        IAccessControl accessControl = IAccessControl(stakingRewardsAddress);
        console2.log("Deployer address: ", msg.sender);
        console2.log("Admin address: ", config.stakingRewardsAdmin);
        console2.log("Admin role assigned: ", accessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), config.stakingRewardsAdmin));
        console2.log("ZKC token address: ", address(stakingRewardsContract.zkc()));
        console2.log("veZKC token address: ", address(stakingRewardsContract.veZKC()));
        console2.log("================================================");
        console2.log("Deployed StakingRewards to: ", stakingRewardsAddress);
    }
}
