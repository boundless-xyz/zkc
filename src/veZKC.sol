// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

// Import our components
import {Votes} from "./components/Votes.sol";
import {Rewards} from "./components/Rewards.sol";
import {Staking} from "./components/Staking.sol";

// Import libraries
import {Checkpoints} from "./libraries/Checkpoints.sol";
import {Constants} from "./libraries/Constants.sol";

import {ZKC} from "./ZKC.sol";

/// @title veZKC - Vote Escrowed ZK Coin
/// @notice Staking contracts for ZKC, granting voting and reward power.
contract veZKC is 
    Initializable, 
    AccessControlUpgradeable, 
    UUPSUpgradeable, 
    EIP712Upgradeable,
    Votes, 
    Rewards, 
    Staking 
{
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address zkcTokenAddress, address _admin) public initializer {
        __ERC721_init("Vote Escrowed ZK Coin", "veZKC");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __EIP712_init("Vote Escrowed ZK Coin", "1");

        _zkcToken = ZKC(zkcTokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        // Initialize checkpoint system
        Checkpoints.initializeGlobalPoint(_globalCheckpoints);
    }

    function _msgSender() internal view override(ContextUpgradeable, Votes, Rewards) returns (address) {
        return msg.sender;
    }

    function _hashTypedDataV4(bytes32 structHash) internal view override(EIP712Upgradeable, Votes, Rewards) returns (bytes32) {
        return EIP712Upgradeable._hashTypedDataV4(structHash);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    /// @dev Support required interfaces
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, Staking)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
