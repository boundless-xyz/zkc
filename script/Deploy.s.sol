// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {ZKC} from "../src/ZKC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployZKC is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        
        address initialMinter1 = vm.envAddress("INITIAL_MINTER_1");
        address initialMinter2 = vm.envAddress("INITIAL_MINTER_2");
        uint256 initialMinter1Amount = vm.envUint("INITIAL_MINTER_1_AMOUNT");
        uint256 initialMinter2Amount = vm.envUint("INITIAL_MINTER_2_AMOUNT");
        bytes32 salt = vm.envBytes32("SALT");
        address owner = vm.envAddress("OWNER");

        address implementation = address(new ZKC());
        console2.log("Deployed ZKC implementation to: ", implementation);
        address zkc = address(
            new ERC1967Proxy{salt: salt}(
                implementation, abi.encodeCall(ZKC.initialize, (initialMinter1, initialMinter2, initialMinter1Amount, initialMinter2Amount, owner))
            )
        );
        console2.log("Deployed ZKC to: ", zkc);

        vm.stopBroadcast();
    }
}
