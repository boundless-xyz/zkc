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
