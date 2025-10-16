// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ConfigLoader, DeploymentConfig} from "./Config.s.sol";
import {BaseDeployment} from "./BaseDeployment.s.sol";
import {ZKC} from "../src/ZKC.sol";
import {veZKC} from "../src/veZKC.sol";
import {StakingRewards} from "../src/rewards/StakingRewards.sol";
import {SupplyCalculator} from "../src/calculators/SupplyCalculator.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * Sample Usage for ZKC rollback:
 *
 * export CHAIN_KEY="anvil"
 * forge script script/Rollback.s.sol:RollbackZKC \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RollbackZKC is BaseDeployment {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC not deployed");
        require(config.zkcImplPrev != address(0), "No previous ZKC implementation found for rollback");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        address currentImpl = _getImplementationAddress(config.zkc);

        // Verify previous implementation has code
        require(_getCodeSize(config.zkcImplPrev) > 0, "Previous implementation has no code");

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing rollback calldata for Safe execution");
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("Current implementation: ", currentImpl);
            console2.log("Rolling back to: ", config.zkcImplPrev);

            // Print Gnosis Safe transaction info for rollback
            bytes memory rollbackCallData = abi.encodeWithSignature("upgradeTo(address)", config.zkcImplPrev);
            console2.log("================================");
            console2.log("================================");
            console2.log("=== GNOSIS SAFE ROLLBACK INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: upgradeTo(address)");
            console2.log("Rollback to Implementation: ", config.zkcImplPrev);
            console2.log("Calldata:");
            console2.logBytes(rollbackCallData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. Upgraded(address indexed implementation)");
            console2.log("   - implementation: ", config.zkcImplPrev);
            console2.log("=====================================");

            console2.log("================================================");
            console2.log("ZKC Rollback Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            console2.log("Rolling back ZKC at: ", config.zkc);
            console2.log("Current implementation: ", currentImpl);
            console2.log("Previous implementation: ", config.zkcImplPrev);

            // Perform rollback using upgradeTo (no initializer needed)
            (bool success,) = config.zkc.call(abi.encodeWithSignature("upgradeTo(address)", config.zkcImplPrev));
            require(success, "Failed to rollback ZKC implementation");

            address rolledBackImpl = _getImplementationAddress(config.zkc);
            console2.log("Rolled back ZKC implementation to: ", rolledBackImpl);
            require(rolledBackImpl == config.zkcImplPrev, "Rollback failed: implementation mismatch");

            vm.stopBroadcast();

            // Verify rollback
            ZKC zkcContract = ZKC(config.zkc);
            IAccessControl accessControl = IAccessControl(config.zkc);
            console2.log("Proxy still points to ZKC: ", address(zkcContract) == config.zkc);
            console2.log(
                "Admin role still assigned: ", accessControl.hasRole(zkcContract.ADMIN_ROLE(), config.zkcAdmin)
            );
            console2.log("Rollback verification successful");
            console2.log("================================================");
            console2.log("ZKC Rollback Complete");
            console2.log("Rolled back to implementation: ", rolledBackImpl);
        }

        // Update deployment.toml: swap current and previous implementations (always do this)
        _updateDeploymentConfig(deploymentKey, "zkc-impl", config.zkcImplPrev);
        _updateDeploymentConfig(deploymentKey, "zkc-impl-prev", currentImpl);
    }
}

/**
 * Sample Usage for veZKC rollback:
 *
 * export CHAIN_KEY="anvil"
 * forge script script/Rollback.s.sol:RollbackVeZKC \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RollbackVeZKC is BaseDeployment {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.veZKC != address(0), "veZKC not deployed");
        require(config.veZKCImplPrev != address(0), "No previous veZKC implementation found for rollback");

        vm.startBroadcast();

        address currentImpl = _getImplementationAddress(config.veZKC);
        console2.log("Rolling back veZKC at: ", config.veZKC);
        console2.log("Current implementation: ", currentImpl);
        console2.log("Previous implementation: ", config.veZKCImplPrev);

        // Verify previous implementation has code
        require(_getCodeSize(config.veZKCImplPrev) > 0, "Previous implementation has no code");

        // Perform rollback by directly upgrading to previous implementation (unsafe)
        (bool success,) =
            config.veZKC.call(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", config.veZKCImplPrev, ""));
        require(success, "Failed to rollback veZKC implementation");

        address rolledBackImpl = _getImplementationAddress(config.veZKC);
        console2.log("Rolled back veZKC implementation to: ", rolledBackImpl);
        require(rolledBackImpl == config.veZKCImplPrev, "Rollback failed: implementation mismatch");

        vm.stopBroadcast();

        // Update deployment.toml: swap current and previous implementations
        _updateDeploymentConfig(deploymentKey, "vezkc-impl", config.veZKCImplPrev);
        _updateDeploymentConfig(deploymentKey, "vezkc-impl-prev", currentImpl);

        // Verify rollback
        veZKC veZKCContract = veZKC(config.veZKC);
        IAccessControl accessControl = IAccessControl(config.veZKC);
        console2.log("Proxy still points to veZKC: ", address(veZKCContract) == config.veZKC);
        console2.log(
            "Admin role still assigned: ", accessControl.hasRole(veZKCContract.ADMIN_ROLE(), config.veZKCAdmin)
        );
        console2.log("ZKC token still configured: ", address(veZKCContract.zkcToken()) == config.zkc);
        console2.log("Rollback verification successful");
        console2.log("================================================");
        console2.log("veZKC Rollback Complete");
        console2.log("Rolled back to implementation: ", rolledBackImpl);
    }
}

/**
 * Sample Usage for StakingRewards rollback:
 *
 * export CHAIN_KEY="anvil"
 * forge script script/Rollback.s.sol:RollbackStakingRewards \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RollbackStakingRewards is BaseDeployment {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.stakingRewards != address(0), "StakingRewards not deployed");
        require(
            config.stakingRewardsImplPrev != address(0), "No previous StakingRewards implementation found for rollback"
        );

        vm.startBroadcast();

        address currentImpl = _getImplementationAddress(config.stakingRewards);
        console2.log("Rolling back StakingRewards at: ", config.stakingRewards);
        console2.log("Current implementation: ", currentImpl);
        console2.log("Previous implementation: ", config.stakingRewardsImplPrev);

        // Verify previous implementation has code
        require(_getCodeSize(config.stakingRewardsImplPrev) > 0, "Previous implementation has no code");

        // Perform rollback by directly upgrading to previous implementation (unsafe)
        (bool success,) = config.stakingRewards.call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", config.stakingRewardsImplPrev, "")
        );
        require(success, "Failed to rollback StakingRewards implementation");

        address rolledBackImpl = _getImplementationAddress(config.stakingRewards);
        console2.log("Rolled back StakingRewards implementation to: ", rolledBackImpl);
        require(rolledBackImpl == config.stakingRewardsImplPrev, "Rollback failed: implementation mismatch");

        vm.stopBroadcast();

        // Update deployment.toml: swap current and previous implementations
        _updateDeploymentConfig(deploymentKey, "staking-rewards-impl", config.stakingRewardsImplPrev);
        _updateDeploymentConfig(deploymentKey, "staking-rewards-impl-prev", currentImpl);

        // Verify rollback
        StakingRewards stakingRewardsContract = StakingRewards(config.stakingRewards);
        IAccessControl accessControl = IAccessControl(config.stakingRewards);
        console2.log("Proxy still points to StakingRewards: ", address(stakingRewardsContract) == config.stakingRewards);
        console2.log(
            "Admin role still assigned: ",
            accessControl.hasRole(stakingRewardsContract.ADMIN_ROLE(), config.stakingRewardsAdmin)
        );
        console2.log("ZKC token still configured: ", address(stakingRewardsContract.zkc()) == config.zkc);
        console2.log("veZKC still configured: ", address(stakingRewardsContract.veZKC()) == config.veZKC);
        console2.log("Rollback verification successful");
        console2.log("================================================");
        console2.log("StakingRewards Rollback Complete");
        console2.log("Rolled back to implementation: ", rolledBackImpl);
    }
}

/**
 * Sample Usage for SupplyCalculator rollback:
 *
 * export CHAIN_KEY="anvil"
 * forge script script/Rollback.s.sol:RollbackSupplyCalculator \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract RollbackSupplyCalculator is BaseDeployment {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.supplyCalculator != address(0), "SupplyCalculator not deployed");
        require(
            config.supplyCalculatorImplPrev != address(0), "No previous SupplyCalculator implementation found for rollback"
        );

        vm.startBroadcast();

        address currentImpl = _getImplementationAddress(config.supplyCalculator);
        console2.log("Rolling back SupplyCalculator at: ", config.supplyCalculator);
        console2.log("Current implementation: ", currentImpl);
        console2.log("Previous implementation: ", config.supplyCalculatorImplPrev);

        // Verify previous implementation has code
        require(_getCodeSize(config.supplyCalculatorImplPrev) > 0, "Previous implementation has no code");

        // Perform rollback by directly upgrading to previous implementation (unsafe)
        (bool success,) = config.supplyCalculator.call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", config.supplyCalculatorImplPrev, "")
        );
        require(success, "Failed to rollback SupplyCalculator implementation");

        address rolledBackImpl = _getImplementationAddress(config.supplyCalculator);
        console2.log("Rolled back SupplyCalculator implementation to: ", rolledBackImpl);
        require(rolledBackImpl == config.supplyCalculatorImplPrev, "Rollback failed: implementation mismatch");

        vm.stopBroadcast();

        // Update deployment.toml: swap current and previous implementations
        _updateDeploymentConfig(deploymentKey, "supply-calculator-impl", config.supplyCalculatorImplPrev);
        _updateDeploymentConfig(deploymentKey, "supply-calculator-impl-prev", currentImpl);

        // Verify rollback
        SupplyCalculator supplyCalculatorContract = SupplyCalculator(config.supplyCalculator);
        IAccessControl accessControl = IAccessControl(config.supplyCalculator);
        console2.log("Proxy still points to SupplyCalculator: ", address(supplyCalculatorContract) == config.supplyCalculator);
        console2.log(
            "Admin role still assigned: ",
            accessControl.hasRole(supplyCalculatorContract.ADMIN_ROLE(), config.supplyCalculatorAdmin)
        );
        console2.log("ZKC token still configured: ", address(supplyCalculatorContract.zkc()) == config.zkc);
        console2.log("Rollback verification successful");
        console2.log("================================================");
        console2.log("SupplyCalculator Rollback Complete");
        console2.log("Rolled back to implementation: ", rolledBackImpl);
    }
}
