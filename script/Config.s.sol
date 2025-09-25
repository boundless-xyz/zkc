// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {stdToml} from "forge-std/StdToml.sol";
import {Vm} from "forge-std/Vm.sol";

struct DeploymentConfig {
    string name;
    uint256 id;
    address zkcAdmin;
    address zkcAdmin2;
    address veZKCAdmin;
    address veZKCAdmin2;
    address stakingRewardsAdmin;
    address stakingRewardsAdmin2;
    address zkc;
    address zkcImpl;
    address zkcImplPrev;
    address zkcDeployer;
    address veZKC;
    address veZKCImpl;
    address veZKCImplPrev;
    address veZKCDeployer;
    address stakingRewards;
    address stakingRewardsImpl;
    address stakingRewardsImplPrev;
    address stakingRewardsDeployer;
    address povwMinter;
    address stakingMinter;
    address circulatingZKC;
    address circulatingZKCImpl;
    address circulatingZKCAdmin;
    string zkcCommit;
    string veZKCCommit;
    string stakingRewardsCommit;
    string circulatingZKCCommit;
}

library ConfigLoader {
    using stdToml for string;

    function loadDeploymentConfig(Vm vm)
        internal
        view
        returns (DeploymentConfig memory config, string memory deploymentKey)
    {
        deploymentKey = findDeploymentKey(vm);
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployment.toml");
        string memory toml = vm.readFile(path);

        string memory keyPrefix = string.concat(".deployment.", deploymentKey);

        config.name = toml.readString(string.concat(keyPrefix, ".name"));
        config.id = toml.readUint(string.concat(keyPrefix, ".id"));
        config.zkcAdmin = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".zkc-admin"));
        config.zkcAdmin2 = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".zkc-admin-2"));
        config.veZKCAdmin = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".vezkc-admin"));
        config.veZKCAdmin2 = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".vezkc-admin-2"));
        config.stakingRewardsAdmin = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".staking-rewards-admin"));
        config.stakingRewardsAdmin2 = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".staking-rewards-admin-2"));
        config.zkc = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".zkc"));
        config.zkcImpl = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".zkc-impl"));
        config.zkcImplPrev = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".zkc-impl-prev"));
        config.zkcDeployer = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".zkc-deployer"));
        config.veZKC = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".vezkc"));
        config.veZKCImpl = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".vezkc-impl"));
        config.veZKCImplPrev = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".vezkc-impl-prev"));
        config.veZKCDeployer = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".vezkc-deployer"));
        config.stakingRewards = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".staking-rewards"));
        config.stakingRewardsImpl = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".staking-rewards-impl"));
        config.stakingRewardsImplPrev =
            _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".staking-rewards-impl-prev"));
        config.stakingRewardsDeployer =
            _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".staking-rewards-deployer"));
        config.povwMinter = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".povw-minter"));
        config.stakingMinter = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".staking-minter"));
        config.circulatingZKC = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".circulating-zkc"));
        config.circulatingZKCImpl = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".circulating-zkc-impl"));
        config.circulatingZKCAdmin = _readAddressOrZero(vm, toml, string.concat(keyPrefix, ".circulating-zkc-admin"));

        // Read per-contract deployment commits, default to empty string if not found
        string memory zkcCommitKey = string.concat(keyPrefix, ".zkc-commit");
        config.zkcCommit = _readStringOrEmpty(toml, zkcCommitKey);

        string memory veZKCCommitKey = string.concat(keyPrefix, ".vezkc-commit");
        config.veZKCCommit = _readStringOrEmpty(toml, veZKCCommitKey);

        string memory stakingRewardsCommitKey = string.concat(keyPrefix, ".staking-rewards-commit");
        config.stakingRewardsCommit = _readStringOrEmpty(toml, stakingRewardsCommitKey);

        return (config, deploymentKey);
    }

    function findDeploymentKey(Vm vm) internal view returns (string memory) {
        // Check CHAIN_KEY env var first
        string memory key = _getEnvStringOrEmpty(vm, "CHAIN_KEY");
        if (bytes(key).length > 0) {
            return key;
        }

        // Fallback to chain ID mapping
        uint256 chainId = block.chainid;
        if (chainId == 31337) {
            return "anvil";
        } else if (chainId == 1) {
            return "ethereum-mainnet";
        } else if (chainId == 11155111) {
            return "ethereum-sepolia";
        } else {
            revert(string.concat("Unknown chain ID: ", vm.toString(chainId)));
        }
    }

    function _getEnvStringOrEmpty(Vm vm, string memory key) private view returns (string memory) {
        try vm.envString(key) returns (string memory value) {
            return value;
        } catch {
            return "";
        }
    }

    function _readStringOrEmpty(string memory toml, string memory key) private view returns (string memory) {
        // Use a simple approach - assume empty if parsing fails
        if (toml.keyExists(key)) {
            return toml.readString(key);
        }
        return "";
    }

    function _readAddressOrZero(Vm vm, string memory toml, string memory key) private view returns (address) {
        // Use a simple approach - assume zero address if parsing fails
        if (toml.keyExists(key)) {
            string memory addrStr = toml.readString(key);
            if (bytes(addrStr).length == 0) return address(0);
            // Try to parse as address string
            if (bytes(addrStr).length == 42 && bytes(addrStr)[0] == "0" && bytes(addrStr)[1] == "x") {
                return vm.parseAddress(addrStr);
            }
        }
        return address(0);
    }
}
