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
     * @notice Updates the deployment commit hash in deployment.toml via FFI
     * @param deploymentKey The chain key (e.g., "anvil", "ethereum-mainnet")
     */
    function _updateDeploymentCommit(string memory deploymentKey) internal {
        string[] memory args = new string[](4);
        args[0] = "git";
        args[1] = "rev-parse";
        args[2] = "--short";
        args[3] = "HEAD";
        
        bytes memory result = vm.ffi(args);
        string memory commit = string(result);
        
        // Update deployment.toml with commit
        string[] memory updateArgs = new string[](6);
        updateArgs[0] = "python3";
        updateArgs[1] = "update_deployment_toml.py";
        updateArgs[2] = "--chain-key";
        updateArgs[3] = deploymentKey;
        updateArgs[4] = "--deployment-commit";
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
}