// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ZKC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ZKCTest is Test {
    ZKC public zkc;

    address public owner = makeAddr("owner");
    address public minter1 = makeAddr("minter1");
    address public minter2 = makeAddr("minter2");
    address public povwMinter = makeAddr("povwMinter");
    address public stakingMinter = makeAddr("stakingMinter");
    address public user = makeAddr("user");

    uint256 public epoch0StartTime;

    function _buildSingleArrayInputs(uint256 amount, uint256 epoch)
        internal
        pure
        returns (uint256[] memory amounts, uint256[] memory epochs)
    {
        amounts = new uint256[](1);
        amounts[0] = amount;
        epochs = new uint256[](1);
        epochs[0] = epoch;
    }

    function deployZKC() internal {
        // Deploy implementation
        ZKC implementation = new ZKC();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            ZKC.initialize.selector,
            minter1,
            minter2,
            implementation.INITIAL_SUPPLY() / 2,
            implementation.INITIAL_SUPPLY() / 2,
            owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        zkc = ZKC(address(proxy));

        // Initialize V2 to set epoch 0 start time
        vm.prank(owner);
        zkc.initializeV2();
        epoch0StartTime = vm.getBlockTimestamp();

        // Grant roles
        vm.startPrank(owner);
        zkc.grantRole(zkc.POVW_MINTER_ROLE(), povwMinter);
        zkc.grantRole(zkc.STAKING_MINTER_ROLE(), stakingMinter);
        vm.stopPrank();
    }
}
