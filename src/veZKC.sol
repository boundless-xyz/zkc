// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

// Import our components
import {Votes} from "./components/Votes.sol";
import {Rewards} from "./components/Rewards.sol";
import {Staking} from "./components/Staking.sol";

// Import libraries  
import {Checkpoints} from "./libraries/Checkpoints.sol";
import {Constants} from "./libraries/Constants.sol";

import {ZKC} from "./ZKC.sol";

/**
 * @title veZKC - Vote Escrowed ZK Coin
 * @notice Vote-escrowed ZKC token system with flexible week-based locking
 * @dev Refactored architecture using modular components:
 *      - Votes: IVotes interface implementation  
 *      - Rewards: IRewards interface implementation
 *      - Staking: NFT functionality and staking operations
 * 
 * Key Features:
 * - Flexible week-based locking (4-208 weeks)
 * - Natural time-based incentives (Curve/Velodrome formula)
 * - Full OpenZeppelin Governor compatibility
 * - Non-transferable governance positions
 * - Unified voting and reward power calculations
 */
contract veZKC is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
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

        _zkcToken = ZKC(zkcTokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        
        // Initialize checkpoint system
        Checkpoints.initializeGlobalPoint(_globalCheckpoints);
    }

    /**
     * @dev Implement abstract function from Votes component
     */
    function _msgSender() internal view override(ContextUpgradeable, Votes, Rewards) returns (address) {
        return msg.sender;
    }

    /**
     * @dev Implement delegates function (used by both Votes and Staking)
     */
    function delegates(address account) public view override(Votes, Staking) returns (address) {
        address delegatee = _delegatee[account];
        return delegatee == address(0) ? account : delegatee;
    }

    /**
     * @dev Authorization function for UUPS upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    /**
     * @dev Support required interfaces
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, Staking)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}