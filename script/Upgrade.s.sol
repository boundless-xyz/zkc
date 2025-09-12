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
 * # Option 1: Safe upgrade with reference build (recommended)
 * # First, create reference build from deployed ZKC commit:
 * export DEPLOYED_COMMIT=$(python3 -c "import tomlkit; print(tomlkit.load(open('deployment.toml'))['deployment']['$CHAIN_KEY']['zkc-commit'])")
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
 *
 * # Option 2: Skip safety checks (WARNING: No reference build needed but unsafe!)
 * export CHAIN_KEY="anvil"
 * export SKIP_SAFETY_CHECKS=true
 * forge script script/Upgrade.s.sol:UpgradeZKC \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
// Base contract with common upgrade logic
abstract contract BaseZKCUpgrade is BaseDeployment {
    /// @notice Deploy implementation and optionally upgrade ZKC contracts
    /// @param proxyAddress The proxy contract address to upgrade
    /// @param initializerData The initializer call data (empty for no initializer)
    /// @return newImpl The new implementation address after deployment/upgrade
    function _deployImplementationAndUpgrade(address proxyAddress, bytes memory initializerData)
        internal
        returns (address newImpl)
    {
        // Check for deployment mode flags
        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        bool skipSafetyChecks = vm.envOr("SKIP_SAFETY_CHECKS", false);

        // Prepare upgrade options
        Options memory opts;

        if (skipSafetyChecks) {
            console2.log("WARNING: Skipping all upgrade safety checks and reference build!");
            opts.unsafeSkipAllChecks = true;
        } else {
            // Get the ZKC commit hash from deployment config for commit-specific reference build
            (DeploymentConfig memory config,) = ConfigLoader.loadDeploymentConfig(vm);
            string memory zkcCommit = config.zkcCommit;
            require(bytes(zkcCommit).length > 0, "ZKC commit hash not found in deployment config");

            // Only set reference contract when doing safety checks
            string memory referenceBuildDir = string.concat("build-info-reference-", zkcCommit);
            opts.referenceContract = string.concat(referenceBuildDir, ":ZKC");
            opts.referenceBuildInfoDir = referenceBuildDir;
            console2.log("Using reference build directory: ", referenceBuildDir);
        }

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Deploying new implementation for Safe upgrade");
            console2.log("Target proxy address: ", proxyAddress);
            address currentImpl = _getImplementationAddress(proxyAddress);
            console2.log("Current implementation: ", currentImpl);

            // Use prepareUpgrade for validation + deployment
            newImpl = Upgrades.prepareUpgrade("ZKC.sol:ZKC", opts);
            console2.log("New implementation deployed: ", newImpl);

            // Print Gnosis Safe transaction info
            _printGnosisSafeInfo(proxyAddress, newImpl, initializerData);
        } else {
            console2.log("Upgrading ZKC at: ", proxyAddress);
            address currentImpl = _getImplementationAddress(proxyAddress);
            console2.log("Current implementation: ", currentImpl);

            // Perform upgrade with optional initializer
            if (initializerData.length > 0) {
                Upgrades.upgradeProxy(proxyAddress, "ZKC.sol:ZKC", initializerData, opts);
            } else {
                Upgrades.upgradeProxy(proxyAddress, "ZKC.sol:ZKC", "", opts);
            }

            newImpl = Upgrades.getImplementationAddress(proxyAddress);
            console2.log("Upgraded ZKC implementation to: ", newImpl);
        }

        return newImpl;
    }

    /// @notice Print Gnosis Safe transaction information for manual upgrades
    /// @param proxyAddress The proxy contract address (target for Gnosis Safe)
    /// @param newImpl The new implementation address
    /// @param initializerData The initializer call data (if any)
    function _printGnosisSafeInfo(address proxyAddress, address newImpl, bytes memory initializerData) internal pure {
        console2.log("================================");
        console2.log("================================");
        console2.log("=== GNOSIS SAFE UPGRADE INFO ===");
        console2.log("Target Address (To): ", proxyAddress);

        if (initializerData.length > 0) {
            // For upgradeToAndCall
            bytes memory callData = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, initializerData);
            console2.log("Function: upgradeToAndCall(address,bytes)");
            console2.log("New Implementation: ", newImpl);
            console2.log("Calldata:");
            console2.logBytes(callData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. Upgraded(address indexed implementation)");
            console2.log("   - implementation: ", newImpl);
            console2.log("2. Initialized(uint8 version)");
            console2.log("   - version: depends on initializer function");
        } else {
            // For upgradeTo
            bytes memory callData = abi.encodeWithSignature("upgradeTo(address)", newImpl);
            console2.log("Function: upgradeTo(address)");
            console2.log("New Implementation: ", newImpl);
            console2.log("Calldata:");
            console2.logBytes(callData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. Upgraded(address indexed implementation)");
            console2.log("   - implementation: ", newImpl);
        }
        console2.log("================================");
    }
}

contract UpgradeZKC is BaseZKCUpgrade {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC not deployed");

        vm.startBroadcast();

        address currentImpl = _getImplementationAddress(config.zkc);
        address newImpl = _deployImplementationAndUpgrade(config.zkc, ""); // No initializer

        vm.stopBroadcast();

        // Update deployment.toml with new implementation and store previous
        _updateDeploymentConfig(deploymentKey, "zkc-impl-prev", currentImpl);
        _updateDeploymentConfig(deploymentKey, "zkc-impl", newImpl);
        _updateZKCCommit(deploymentKey);

        // Print Gnosis Safe transaction info (only if not in GNOSIS_EXECUTE mode)
        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        if (!gnosisExecute) {
            _printGnosisSafeInfo(config.zkc, newImpl, "");
        }

        // Verify results
        if (gnosisExecute) {
            console2.log("================================================");
            console2.log("ZKC Implementation Deployment Complete");
            console2.log("New Implementation: ", newImpl);
            console2.log("Proxy NOT upgraded - use Gnosis Safe to complete upgrade");
        } else {
            ZKC zkcContract = ZKC(config.zkc);
            console2.log("Proxy still points to ZKC: ", address(zkcContract) == config.zkc);
            console2.log("Implementation updated: ", newImpl != config.zkcImpl);
            console2.log("================================================");
            console2.log("ZKC Upgrade Complete");
            console2.log("New Implementation: ", newImpl);
        }
    }
}

/**
 * Sample Usage for ZKC upgrade with initializeV2:
 *
 * # Option 1: Safe upgrade with reference build (recommended)
 * # First, create reference build from deployed ZKC commit:
 * export DEPLOYED_COMMIT=$(python3 -c "import tomlkit; print(tomlkit.load(open('deployment.toml'))['deployment']['$CHAIN_KEY']['zkc-commit'])")
 * WORKTREE_PATH="../zkc-reference-${DEPLOYED_COMMIT}"
 * git worktree add "$WORKTREE_PATH" "$DEPLOYED_COMMIT"
 * cd "$WORKTREE_PATH"
 * forge build --profile reference
 * cp -R out-reference/build-info "$OLDPWD/build-info-reference"
 * cd "$OLDPWD"
 *
 * # Then run upgrade:
 * export CHAIN_KEY="anvil"
 * forge script script/Upgrade.s.sol:UpgradeZKC_InitV2 \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpgradeZKC_InitV2 is BaseZKCUpgrade {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC not deployed");

        vm.startBroadcast();

        address currentImpl = _getImplementationAddress(config.zkc);
        bytes memory initializerData = abi.encodeCall(ZKC.initializeV2, ());
        address newImpl = _deployImplementationAndUpgrade(config.zkc, initializerData);

        vm.stopBroadcast();

        // Update deployment.toml with new implementation and store previous
        _updateDeploymentConfig(deploymentKey, "zkc-impl-prev", currentImpl);
        _updateDeploymentConfig(deploymentKey, "zkc-impl", newImpl);
        _updateZKCCommit(deploymentKey);

        // Print Gnosis Safe transaction info (only if not in GNOSIS_EXECUTE mode)
        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);
        if (!gnosisExecute) {
            _printGnosisSafeInfo(config.zkc, newImpl, initializerData);
        }

        // Verify results
        if (gnosisExecute) {
            console2.log("================================================");
            console2.log("ZKC Implementation Deployment Complete");
            console2.log("New Implementation: ", newImpl);
            console2.log("Proxy NOT upgraded - use Gnosis Safe to complete upgrade");
            console2.log("Note: initializeV2 will be called when Safe executes upgrade");
        } else {
            ZKC zkcContract = ZKC(config.zkc);
            console2.log("Proxy still points to ZKC: ", address(zkcContract) == config.zkc);
            console2.log("Implementation updated: ", newImpl != config.zkcImpl);
            console2.log("initializeV2 called during upgrade");
            console2.log("================================================");
            console2.log("ZKC Upgrade with InitV2 Complete");
            console2.log("New Implementation: ", newImpl);
        }
    }
}

/**
 * Sample Usage for ZKC Start Epochs (initializeV3 only, no upgrade):
 *
 * export CHAIN_KEY="anvil"
 * forge script script/Upgrade.s.sol:ZKCStartEpochs \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 *
 * Note: This script calls initializeV3 to start epochs. Requires admin role.
 */
contract ZKCStartEpochs is BaseDeployment {
    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.zkc != address(0), "ZKC not deployed");

        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);

        if (gnosisExecute) {
            console2.log("GNOSIS_EXECUTE=true: Preparing initializeV3 calldata for Safe execution");
            console2.log("ZKC Contract: ", config.zkc);

            // Print Gnosis Safe transaction info for initializeV3
            bytes memory initV3CallData = abi.encodeCall(ZKC.initializeV3, ());
            console2.log("================================");
            console2.log("================================");
            console2.log("=== GNOSIS SAFE INITIALIZEV3 INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: initializeV3()");
            console2.log("Calldata:");
            console2.logBytes(initV3CallData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. Custom ZKC events related to epoch initialization");
            console2.log("   - Check ZKC contract for specific events emitted by initializeV3");
            console2.log("====================================");

            console2.log("================================================");
            console2.log("ZKC InitializeV3 Calldata Ready");
            console2.log("Transaction NOT executed - use Gnosis Safe to execute");
        } else {
            vm.startBroadcast();

            ZKC zkcContract = ZKC(config.zkc);

            console2.log("Starting ZKC epochs by calling initializeV3...");
            console2.log("ZKC Contract: ", config.zkc);
            console2.log("Current epoch0StartTime: ", zkcContract.epoch0StartTime());

            // Call initializeV3 to start epochs
            zkcContract.initializeV3();

            vm.stopBroadcast();

            // Print Gnosis Safe transaction info for initializeV3
            bytes memory initV3CallData = abi.encodeCall(ZKC.initializeV3, ());
            console2.log("================================");
            console2.log("================================");
            console2.log("=== GNOSIS SAFE INITIALIZEV3 INFO ===");
            console2.log("Target Address (To): ", config.zkc);
            console2.log("Function: initializeV3()");
            console2.log("Calldata:");
            console2.logBytes(initV3CallData);
            console2.log("");
            console2.log("Expected Events on Successful Execution:");
            console2.log("1. Custom ZKC events related to epoch initialization");
            console2.log("   - Check ZKC contract for specific events emitted by initializeV3");
            console2.log("====================================");

            // Verify epoch start
            uint256 newEpoch0StartTime = zkcContract.epoch0StartTime();
            console2.log("New epoch0StartTime: ", newEpoch0StartTime);
            console2.log("Block timestamp: ", block.timestamp);
            console2.log("Epochs started: ", newEpoch0StartTime != type(uint256).max && newEpoch0StartTime != 0);
            console2.log("================================================");
            console2.log("ZKC Epochs Started Successfully");
            console2.log("Epoch 0 Start Time: ", newEpoch0StartTime);
        }
    }
}

/**
 * Sample Usage for veZKC upgrade:
 *
 * # First, create reference build from deployed veZKC commit:
 * export DEPLOYED_COMMIT=$(python3 -c "import tomlkit; print(tomlkit.load(open('deployment.toml'))['deployment']['$CHAIN_KEY']['vezkc-commit'])")
 * WORKTREE_PATH="../vezkc-reference-${DEPLOYED_COMMIT}"
 * git worktree add "$WORKTREE_PATH" "$DEPLOYED_COMMIT"
 * cd "$WORKTREE_PATH"
 * forge build --profile reference
 * cp -R out-reference/build-info "$OLDPWD/build-info-reference"
 * cd "$OLDPWD"
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

        // Check for skip safety checks flag
        bool skipSafetyChecks = vm.envOr("SKIP_SAFETY_CHECKS", false);

        // Prepare upgrade options with reference contract
        Options memory opts;

        if (skipSafetyChecks) {
            console2.log("WARNING: Skipping all upgrade safety checks and reference build!");
            opts.unsafeSkipAllChecks = true;
        } else {
            // Get the veZKC commit hash from deployment config for commit-specific reference build
            string memory veZKCCommit = config.veZKCCommit;
            require(bytes(veZKCCommit).length > 0, "veZKC commit hash not found in deployment config");

            string memory referenceBuildDir = string.concat("build-info-reference-", veZKCCommit);
            opts.referenceContract = string.concat(referenceBuildDir, ":veZKC");
            opts.referenceBuildInfoDir = referenceBuildDir;
            console2.log("Using reference build directory: ", referenceBuildDir);
        }

        console2.log("Upgrading veZKC at: ", config.veZKC);
        address currentImpl = _getImplementationAddress(config.veZKC);
        console2.log("Current implementation: ", currentImpl);

        // Perform safe upgrade
        Upgrades.upgradeProxy(
            config.veZKC,
            "veZKC.sol:veZKC",
            "", // No reinitializer
            opts
        );

        address newImpl = Upgrades.getImplementationAddress(config.veZKC);
        console2.log("Upgraded veZKC implementation to: ", newImpl);

        vm.stopBroadcast();

        // Update deployment.toml with new implementation and store previous
        _updateDeploymentConfig(deploymentKey, "vezkc-impl-prev", currentImpl);
        _updateDeploymentConfig(deploymentKey, "vezkc-impl", newImpl);
        _updateVeZKCCommit(deploymentKey);

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
 * # First, create reference build from deployed StakingRewards commit:
 * export DEPLOYED_COMMIT=$(python3 -c "import tomlkit; print(tomlkit.load(open('deployment.toml'))['deployment']['$CHAIN_KEY']['staking-rewards-commit'])")
 * WORKTREE_PATH="../staking-rewards-reference-${DEPLOYED_COMMIT}"
 * git worktree add "$WORKTREE_PATH" "$DEPLOYED_COMMIT"
 * cd "$WORKTREE_PATH"
 * forge build --profile reference
 * cp -R out-reference/build-info "$OLDPWD/build-info-reference"
 * cd "$OLDPWD"
 *
 * # Then run upgrade:
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

        // Check for skip safety checks flag
        bool skipSafetyChecks = vm.envOr("SKIP_SAFETY_CHECKS", false);

        // Prepare upgrade options with reference contract
        Options memory opts;

        if (skipSafetyChecks) {
            console2.log("WARNING: Skipping all upgrade safety checks and reference build!");
            opts.unsafeSkipAllChecks = true;
        } else {
            // Get the StakingRewards commit hash from deployment config for commit-specific reference build
            string memory stakingRewardsCommit = config.stakingRewardsCommit;
            require(bytes(stakingRewardsCommit).length > 0, "StakingRewards commit hash not found in deployment config");

            string memory referenceBuildDir = string.concat("build-info-reference-", stakingRewardsCommit);
            opts.referenceContract = string.concat(referenceBuildDir, ":StakingRewards");
            opts.referenceBuildInfoDir = referenceBuildDir;
            console2.log("Using reference build directory: ", referenceBuildDir);
        }

        console2.log("Upgrading StakingRewards at: ", config.stakingRewards);
        address currentImpl = _getImplementationAddress(config.stakingRewards);
        console2.log("Current implementation: ", currentImpl);

        // Perform safe upgrade
        Upgrades.upgradeProxy(
            config.stakingRewards,
            "StakingRewards.sol:StakingRewards",
            "", // No reinitializer
            opts
        );

        address newImpl = Upgrades.getImplementationAddress(config.stakingRewards);
        console2.log("Upgraded StakingRewards implementation to: ", newImpl);

        vm.stopBroadcast();

        // Update deployment.toml with new implementation and store previous
        _updateDeploymentConfig(deploymentKey, "staking-rewards-impl-prev", currentImpl);
        _updateDeploymentConfig(deploymentKey, "staking-rewards-impl", newImpl);
        _updateStakingRewardsCommit(deploymentKey);

        // Verify upgrade
        StakingRewards stakingRewardsContract = StakingRewards(config.stakingRewards);
        console2.log("Proxy still points to StakingRewards: ", address(stakingRewardsContract) == config.stakingRewards);
        console2.log("Implementation updated: ", newImpl != config.stakingRewardsImpl);
        console2.log("ZKC configured: ", address(stakingRewardsContract.zkc()));
        console2.log("veZKC configured: ", address(stakingRewardsContract.veZKC()));
        console2.log("ZKC token still configured: ", address(stakingRewardsContract.zkc()) == config.zkc);
        console2.log("veZKC still configured: ", address(stakingRewardsContract.veZKC()) == config.veZKC);
        console2.log("================================================");
        console2.log("StakingRewards Upgrade Complete");
        console2.log("New Implementation: ", newImpl);
    }
}
