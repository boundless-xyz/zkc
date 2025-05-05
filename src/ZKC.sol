// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ZKC is 
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    address public initialMinter1;
    address public initialMinter2;
    uint256 public initialMinter1Remaining;
    uint256 public initialMinter2Remaining;

    bytes32 public immutable ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public immutable MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialMinter1,
        address _initialMinter2,
        uint256 _initialMinter1Amount,
        uint256 _initialMinter2Amount,
        address _owner
    ) public initializer {
        __ERC20_init("ZK Coin", "ZKC");
        __ERC20Permit_init("ZK Coin");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        initialMinter1 = _initialMinter1;
        initialMinter2 = _initialMinter2;
        initialMinter1Remaining = _initialMinter1Amount;
        initialMinter2Remaining = _initialMinter2Amount;
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function initialMint(address[] calldata recipients, uint256[] calldata amounts) public {
        require(recipients.length == amounts.length);
        require(msg.sender == initialMinter1 || msg.sender == initialMinter2);

        uint256 minted = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 amount = amounts[i];
            _mint(recipients[i], amount);
            minted += amount;
        }

        if (msg.sender == initialMinter1) {
            initialMinter1Remaining -= minted;
        } else {
            initialMinter2Remaining -= minted;
        }
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}