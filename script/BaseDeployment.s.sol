// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title BaseDeployment
 * @notice Base contract for deployment and upgrade scripts with shared functionality
 */
abstract contract BaseDeployment is Script {
    /**
     * @notice Updates a specific field in deployment.toml via FFI
     * @param deploymentKey The chain key (e.g., "anvil", "ethereum-mainnet")
     * @param key The field name to update (e.g., "zkc", "vezkc-impl")
     * @param value The address value to set
     */
    function _updateDeploymentConfig(string memory deploymentKey, string memory key, address value) internal {
        string[] memory args = new string[](6);
        args[0] = "python3";
        args[1] = "update_deployment_toml.py";
        args[2] = "--chain-key";
        args[3] = deploymentKey;
        args[4] = string.concat("--", key);
        args[5] = Strings.toHexString(value);

        vm.ffi(args);
    }

    /**
     * @notice Removes an admin from deployment.toml by checking both admin fields and clearing the matching one
     * @param deploymentKey The chain key (e.g., "anvil", "ethereum-mainnet")
     * @param adminToRemove The admin address to remove
     * @param adminField1 First admin field to check (e.g., "zkc-admin")
     * @param adminField2 Second admin field to check (e.g., "zkc-admin-2")
     */
    function _removeAdminFromToml(
        string memory deploymentKey,
        address adminToRemove,
        string memory adminField1,
        string memory adminField2
    ) internal {
        string[] memory args = new string[](8);
        args[0] = "python3";
        args[1] = "update_deployment_toml.py";
        args[2] = "--chain-key";
        args[3] = deploymentKey;
        args[4] = "--remove-admin";
        args[5] = Strings.toHexString(adminToRemove);
        args[6] = adminField1;
        args[7] = adminField2;

        vm.ffi(args);
    }

    /**
     * @notice Updates the ZKC contract commit hash in deployment.toml via FFI
     * @param deploymentKey The chain key (e.g., "anvil", "ethereum-mainnet")
     */
    function _updateZKCCommit(string memory deploymentKey) internal {
        string[] memory args = new string[](4);
        args[0] = "git";
        args[1] = "rev-parse";
        args[2] = "--short";
        args[3] = "HEAD";

        bytes memory result = vm.ffi(args);
        string memory commit = string(result);

        // Update deployment.toml with ZKC commit
        string[] memory updateArgs = new string[](6);
        updateArgs[0] = "python3";
        updateArgs[1] = "update_deployment_toml.py";
        updateArgs[2] = "--chain-key";
        updateArgs[3] = deploymentKey;
        updateArgs[4] = "--zkc-commit";
        updateArgs[5] = commit;

        vm.ffi(updateArgs);
    }

    /**
     * @notice Updates the veZKC contract commit hash in deployment.toml via FFI
     * @param deploymentKey The chain key (e.g., "anvil", "ethereum-mainnet")
     */
    function _updateVeZKCCommit(string memory deploymentKey) internal {
        string[] memory args = new string[](4);
        args[0] = "git";
        args[1] = "rev-parse";
        args[2] = "--short";
        args[3] = "HEAD";

        bytes memory result = vm.ffi(args);
        string memory commit = string(result);

        // Update deployment.toml with veZKC commit
        string[] memory updateArgs = new string[](6);
        updateArgs[0] = "python3";
        updateArgs[1] = "update_deployment_toml.py";
        updateArgs[2] = "--chain-key";
        updateArgs[3] = deploymentKey;
        updateArgs[4] = "--vezkc-commit";
        updateArgs[5] = commit;

        vm.ffi(updateArgs);
    }

    /**
     * @notice Updates the StakingRewards contract commit hash in deployment.toml via FFI
     * @param deploymentKey The chain key (e.g., "anvil", "ethereum-mainnet")
     */
    function _updateStakingRewardsCommit(string memory deploymentKey) internal {
        string[] memory args = new string[](4);
        args[0] = "git";
        args[1] = "rev-parse";
        args[2] = "--short";
        args[3] = "HEAD";

        bytes memory result = vm.ffi(args);
        string memory commit = string(result);

        // Update deployment.toml with StakingRewards commit
        string[] memory updateArgs = new string[](6);
        updateArgs[0] = "python3";
        updateArgs[1] = "update_deployment_toml.py";
        updateArgs[2] = "--chain-key";
        updateArgs[3] = deploymentKey;
        updateArgs[4] = "--staking-rewards-commit";
        updateArgs[5] = commit;

        vm.ffi(updateArgs);
    }

    /**
     * @notice Updates the SupplyCalculator contract commit hash in deployment.toml via FFI
     * @param deploymentKey The chain key (e.g., "anvil", "ethereum-mainnet")
     */
    function _updateSupplyCalculatorCommit(string memory deploymentKey) internal {
        string[] memory args = new string[](4);
        args[0] = "git";
        args[1] = "rev-parse";
        args[2] = "--short";
        args[3] = "HEAD";

        bytes memory result = vm.ffi(args);
        string memory commit = string(result);

        // Update deployment.toml with SupplyCalculator commit
        string[] memory updateArgs = new string[](6);
        updateArgs[0] = "python3";
        updateArgs[1] = "update_deployment_toml.py";
        updateArgs[2] = "--chain-key";
        updateArgs[3] = deploymentKey;
        updateArgs[4] = "--supply-calculator-commit";
        updateArgs[5] = commit;

        vm.ffi(updateArgs);
    }

    /// @notice Get the current implementation address from ERC1967 proxy
    /// @param proxy The proxy contract address
    /// @return impl The implementation address
    function _getImplementationAddress(address proxy) internal view returns (address impl) {
        // ERC1967 implementation storage slot
        // bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        // Read from the proxy contract's storage
        bytes32 result = vm.load(proxy, slot);
        impl = address(uint160(uint256(result)));
    }

    /// @notice Get the size of contract code at an address
    function _getCodeSize(address addr) internal view returns (uint256 size) {
        assembly {
            size := extcodesize(addr)
        }
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

        bytes memory callData = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, initializerData);
        console2.log("Function: upgradeToAndCall(address,bytes)");
        console2.log("New Implementation: ", newImpl);

        if (initializerData.length > 0) {
            console2.log("Initializer Data:");
            console2.logBytes(initializerData);
        } else {
            console2.log("Initializer Data: 0x (empty - no function call)");
        }

        console2.log("Calldata:");
        console2.logBytes(callData);
        console2.log("");
        console2.log("Expected Events on Successful Execution:");
        console2.log("1. Upgraded(address indexed implementation)");
        console2.log("   - implementation: ", newImpl);

        if (initializerData.length > 0) {
            console2.log("2. Initialized(uint8 version)");
            console2.log("   - version: depends on initializer function");
        }
    }
}
