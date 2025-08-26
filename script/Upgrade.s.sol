// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ConfigLoader, DeploymentConfig} from "./Config.s.sol";
import {BaseDeployment} from "./BaseDeployment.s.sol";
import {ZKC} from "../src/ZKC.sol";
import {veZKC} from "../src/veZKC.sol";
import {StakingRewards} from "../src/rewards/StakingRewards.sol";

/**
 * Sample Usage for ZKC upgrade:
 *
 * # First, create reference build from deployed commit:
 * export DEPLOYED_COMMIT=$(python3 -c "import tomlkit; print(tomlkit.load(open('deployment.toml'))['deployment']['$CHAIN_KEY']['deployment-commit'])")
 * WORKTREE_PATH="../zkc-reference-${DEPLOYED_COMMIT}"
 * git worktree add "$WORKTREE_PATH" "$DEPLOYED_COMMIT"
 * cd "$WORKTREE_PATH"
 * forge build --profile reference
 * cp -R out-reference/build-info "$OLDPWD/build-info-reference"
 * cd "$OLDPWD"
 *
 * # Then run upgrade:
 * export CHAIN_KEY="anvil"
 * forge script script/Upgrade.s.sol:UpgradeZKC \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpgradeZKC is BaseDeployment {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC not deployed");

        vm.startBroadcast();

        // Prepare upgrade options with reference contract
        Options memory opts;
        opts.referenceContract = "build-info-reference:ZKC";
        opts.referenceBuildInfoDir = "build-info-reference";

        console2.log("Upgrading ZKC at: ", config.zkc);
        console2.log("Current implementation: ", Upgrades.getImplementationAddress(config.zkc));

        // Perform safe upgrade
        Upgrades.upgradeProxy(
            config.zkc,
            "ZKC.sol:ZKC",
            "",  // No reinitializer
            opts
        );

        address newImpl = Upgrades.getImplementationAddress(config.zkc);
        console2.log("Upgraded ZKC implementation to: ", newImpl);

        vm.stopBroadcast();

        // Update deployment.toml with new implementation
        _updateDeploymentConfig(deploymentKey, "zkc-impl", newImpl);
        _updateDeploymentCommit(deploymentKey);

        // Verify upgrade
        ZKC zkcContract = ZKC(config.zkc);
        console2.log("Proxy still points to ZKC: ", address(zkcContract) == config.zkc);
        console2.log("Implementation updated: ", newImpl != config.zkcImpl);
        console2.log("================================================");
        console2.log("ZKC Upgrade Complete");
        console2.log("New Implementation: ", newImpl);
    }

}

/**
 * Sample Usage for veZKC upgrade:
 *
 * # First, create reference build from deployed commit (same as above)
 *
 * # Then run upgrade:
 * export CHAIN_KEY="anvil"
 * forge script script/Upgrade.s.sol:UpgradeVeZKC \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpgradeVeZKC is BaseDeployment {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.veZKC != address(0), "veZKC not deployed");

        vm.startBroadcast();

        // Prepare upgrade options with reference contract
        Options memory opts;
        opts.referenceContract = "build-info-reference:veZKC";
        opts.referenceBuildInfoDir = "build-info-reference";

        console2.log("Upgrading veZKC at: ", config.veZKC);
        console2.log("Current implementation: ", Upgrades.getImplementationAddress(config.veZKC));

        // Perform safe upgrade
        Upgrades.upgradeProxy(
            config.veZKC,
            "veZKC.sol:veZKC",
            "",  // No reinitializer
            opts
        );

        address newImpl = Upgrades.getImplementationAddress(config.veZKC);
        console2.log("Upgraded veZKC implementation to: ", newImpl);

        vm.stopBroadcast();

        // Update deployment.toml with new implementation
        _updateDeploymentConfig(deploymentKey, "vezkc-impl", newImpl);
        _updateDeploymentCommit(deploymentKey);

        // Verify upgrade
        veZKC veZKCContract = veZKC(config.veZKC);
        console2.log("Proxy still points to veZKC: ", address(veZKCContract) == config.veZKC);
        console2.log("Implementation updated: ", newImpl != config.veZKCImpl);
        console2.log("ZKC token still configured: ", address(veZKCContract.zkcToken()) == config.zkc);
        console2.log("================================================");
        console2.log("veZKC Upgrade Complete");
        console2.log("New Implementation: ", newImpl);
    }

}

/**
 * Sample Usage for StakingRewards upgrade:
 *
 * export CHAIN_KEY="anvil"
 * forge script script/Upgrade.s.sol:UpgradeStakingRewards \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpgradeStakingRewards is BaseDeployment {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.stakingRewards != address(0), "StakingRewards not deployed");

        vm.startBroadcast();

        // Prepare upgrade options with reference contract
        Options memory opts;
        opts.referenceContract = "build-info-reference:StakingRewards";
        opts.referenceBuildInfoDir = "build-info-reference";

        console2.log("Upgrading StakingRewards at: ", config.stakingRewards);
        console2.log("Current implementation: ", Upgrades.getImplementationAddress(config.stakingRewards));

        // Perform safe upgrade
        Upgrades.upgradeProxy(
            config.stakingRewards,
            "StakingRewards.sol:StakingRewards",
            "",  // No reinitializer
            opts
        );

        address newImpl = Upgrades.getImplementationAddress(config.stakingRewards);
        console2.log("Upgraded StakingRewards implementation to: ", newImpl);

        vm.stopBroadcast();

        // Update deployment.toml with new implementation
        _updateDeploymentConfig(deploymentKey, "staking-rewards-impl", newImpl);
        _updateDeploymentCommit(deploymentKey);

        // Verify upgrade
        StakingRewards stakingRewardsContract = StakingRewards(config.stakingRewards);
        console2.log("Proxy still points to StakingRewards: ", address(stakingRewardsContract) == config.stakingRewards);
        console2.log("Implementation updated: ", newImpl != config.stakingRewardsImpl);
        console2.log("ZKC token still configured: ", address(stakingRewardsContract.zkc()) == config.zkc);
        console2.log("veZKC still configured: ", address(stakingRewardsContract.veZKC()) == config.veZKC);
        console2.log("================================================");
        console2.log("StakingRewards Upgrade Complete");
        console2.log("New Implementation: ", newImpl);
    }

}
