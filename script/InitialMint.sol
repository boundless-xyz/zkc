// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {ZKC} from "../src/ZKC.sol";

/**
 * Sample Usage (addresses are Anvil default accounts):
 *
 * # Address of the already deployed ZKC contract
 * export ZKC_ADDRESS="0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555"
 *
 * # Comma-separated list of recipient addresses
 * export RECIPIENTS="0x139Ce48CD89155a443786FFBE32185Bb50Ae2b69"
 * # Comma-separated list of amounts (in ZKC, not wei)
 * export AMOUNTS="550000000"
 *
 *
 * Dry-run:
 * forge script script/InitialMint.sol:InitialMint \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --rpc-url http://127.0.0.1:8545
 *
 *
 * forge script script/InitialMint.sol:InitialMint \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 */
contract InitialMint is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Get contract address and create instance
        address zkcAddress = vm.envAddress("ZKC_ADDRESS");
        ZKC zkcContract = ZKC(zkcAddress);

        // Get recipients and amounts from env
        string[] memory recipientsStrings = vm.envString("RECIPIENTS", ",");
        string[] memory amountsStrings = vm.envString("AMOUNTS", ",");

        // Parse recipients
        address[] memory recipients = new address[](recipientsStrings.length);
        for (uint256 i = 0; i < recipientsStrings.length; i++) {
            recipients[i] = vm.parseAddress(recipientsStrings[i]);
        }

        // Parse amounts and convert from ZKC to wei
        uint256[] memory amounts = new uint256[](amountsStrings.length);
        for (uint256 i = 0; i < amountsStrings.length; i++) {
            // Convert from ZKC to wei by multiplying by 10^18
            amounts[i] = vm.parseUint(amountsStrings[i]) * 10 ** 18;
        }

        require(recipients.length == amounts.length, "Recipients and amounts arrays must have same length");

        console2.log("Minting...");
        // Perform initial mint
        zkcContract.initialMint(recipients, amounts);

        vm.stopBroadcast();

        // Print recipient balances
        console2.log("================================================");
        console2.log("Recipient Balances:");
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 balance = zkcContract.balanceOf(recipients[i]);
            console2.log("Recipient: ", recipients[i]);
            console2.log("Balance (ZKC): ", balance / 10 ** 18);
        }
        console2.log("================================================");
    }
}
