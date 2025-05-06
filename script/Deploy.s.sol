// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {ZKC} from "../src/ZKC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * Sample Usage (addresses are Anvil default accounts):
 *
 * export INITIAL_MINTER_1="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
 * export INITIAL_MINTER_2="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
 * export TOTAL_INITIAL_SUPPLY="1000000000000000000000000000"
 * export INITIAL_MINTER_1_AMOUNT="550000000000000000000000000"
 * export INITIAL_MINTER_2_AMOUNT="450000000000000000000000000"
 * export SALT="0x0000000000000000000000000000000000000000000000000000000000000001"
 * export OWNER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
 *
 * forge script script/Deploy.s.sol:DeployZKC \
 * --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 * --broadcast \
 * --rpc-url http://127.0.0.1:8545
 */
contract DeployZKC is Script {
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
        address owner = vm.envAddress("OWNER");

        address implementation = address(new ZKC());
        console2.log("Deployed ZKC implementation to: ", implementation);
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            implementation,
            abi.encodeCall(
                ZKC.initialize, (initialMinter1, initialMinter2, initialMinter1Amount, initialMinter2Amount, owner)
            )
        );
        address zkc = address(proxy);
        console2.log("Deployed ZKC to: ", zkc);
        console2.logBytes32(address(proxy).codehash);

        vm.stopBroadcast();
    }
}
