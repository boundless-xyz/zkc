// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
contract veZKC is Initializable, AccessControlUpgradeable, UUPSUpgradeable, EIP712Upgradeable, Votes, Rewards, Staking {
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// @notice Returns the ZKC token address
    function zkcToken() external view returns (address) {
        return address(_zkcToken);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the veZKC contract with ZKC token and admin setup
    /// @dev Sets up the ERC721 token, access control, and checkpoint system. Can only be called once during deployment.
    /// @param zkcTokenAddress Address of the ZKC token contract that users will stake
    /// @param _admin Address to be granted admin role for contract upgrades and management
    function initialize(address zkcTokenAddress, address _admin) public initializer {
        __ERC721_init("Vote Escrowed ZK Coin", "veZKC");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __EIP712_init("Vote Escrowed ZK Coin", "1");

        require(zkcTokenAddress != address(0), "ZKC token address cannot be zero address");
        require(_admin != address(0), "Admin cannot be zero address");

        _zkcToken = ZKC(zkcTokenAddress);
        _grantRole(ADMIN_ROLE, _admin);

        // Initialize checkpoint system
        Checkpoints.initializeGlobalPoint(_globalCheckpoints);
    }

    /// @notice Get the message sender (required for context resolution)
    /// @return The address of the message sender
    function _msgSender() internal view override(ContextUpgradeable, Votes, Rewards) returns (address) {
        return msg.sender;
    }

    /// @notice Hash typed data for EIP-712 signatures
    /// @param structHash The struct hash to be processed
    /// @return The final hash for signature verification
    function _hashTypedDataV4(bytes32 structHash)
        internal
        view
        override(EIP712Upgradeable, Votes, Rewards)
        returns (bytes32)
    {
        return EIP712Upgradeable._hashTypedDataV4(structHash);
    }

    /// @notice Authorize contract upgrades (UUPS pattern)
    /// @dev Only accounts with ADMIN_ROLE can authorize upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    /// @notice Support required interfaces for ERC165
    /// @param interfaceId The interface identifier to check
    /// @return bool True if the interface is supported
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, Staking)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
