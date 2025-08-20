// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Supply} from "./libraries/Supply.sol";
import {IZKC} from "./interfaces/IZKC.sol";

/// @title ZKC - ZK Coin
/// @notice The main ZKC token contract with epoch-based emissions
/// @dev Implements upgradeable ERC20 with permit functionality and role-based minting
contract ZKC is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, UUPSUpgradeable, IZKC {
    /// @notice Address of the first initial minter
    address public initialMinter1;
    
    /// @notice Address of the second initial minter
    address public initialMinter2;
    
    /// @notice Remaining mintable amount for the first initial minter
    uint256 public initialMinter1Remaining;
    
    /// @notice Remaining mintable amount for the second initial minter
    uint256 public initialMinter2Remaining;

    /// @notice Admin role identifier
    bytes32 public immutable ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    
    /// @notice General minter role identifier
    bytes32 public immutable MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Initial token supply (1 billion ZKC)
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18; 

    /// @notice Basis points constant for percentage calculations
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Duration of each epoch in seconds (2 days)
    uint256 public constant EPOCH_DURATION = 2 days;
    
    /// @notice Number of epochs per year
    uint256 public constant EPOCHS_PER_YEAR = 182;
    
    /// @notice Percentage of emissions allocated to PoVW rewards (75%)
    uint256 public constant POVW_ALLOCATION_BPS = 7500;
    
    /// @notice Percentage of emissions allocated to staking rewards (25%)
    uint256 public constant STAKING_ALLOCATION_BPS = 2500;   

    /// @notice Role identifier for PoVW reward minters
    bytes32 public immutable POVW_MINTER_ROLE = keccak256("POVW_MINTER_ROLE");
    
    /// @notice Role identifier for staking reward minters
    bytes32 public immutable STAKING_MINTER_ROLE = keccak256("STAKING_MINTER_ROLE");

    /// @notice Timestamp when the contract was deployed (epoch 0 start)
    uint256 public deploymentTime;

    /// @notice Total amount of PoVW rewards minted
    uint256 public poVWMinted;
    
    /// @notice Total amount of staking rewards minted
    uint256 public stakingMinted;

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

        require(_initialMinter1Amount + _initialMinter2Amount == INITIAL_SUPPLY);

        initialMinter1 = _initialMinter1;
        initialMinter2 = _initialMinter2;
        initialMinter1Remaining = _initialMinter1Amount;
        initialMinter2Remaining = _initialMinter2Amount;
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    // On upgrade, set the deployment time to initiate the start of the first epoch.
    function initializeV2() public reinitializer(2) {
        deploymentTime = block.timestamp;
    }

    /// @inheritdoc IZKC
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

    /// @inheritdoc IZKC
    function mintPoVWRewardsForRecipient(address recipient, uint256 amount) external onlyRole(POVW_MINTER_ROLE) {
        _mintPoVWRewardsForRecipient(recipient, amount);
        emit PoVWRewardsClaimed(recipient, amount);
    }

    /// @inheritdoc IZKC
    function mintStakingRewardsForRecipient(address recipient, uint256 amount) external onlyRole(STAKING_MINTER_ROLE) {
        _mintStakingRewardsForRecipient(recipient, amount);
        emit StakingRewardsClaimed(recipient, amount);
    }

    function _mintPoVWRewardsForRecipient(address recipient, uint256 amount) internal {
        uint256 totalEmissions = getTotalPoVWEmissionsAtEpochStart(getCurrentEpoch());
        uint256 mintedTotal = poVWMinted + amount;
        if (mintedTotal > totalEmissions) {
            revert TotalAllocationExceeded();
        }

        poVWMinted = mintedTotal;
        _mint(recipient, amount);
    }

    function _mintStakingRewardsForRecipient(address recipient, uint256 amount) internal {
        uint256 totalEmissions = getTotalStakingEmissionsAtEpochStart(getCurrentEpoch());
        uint256 mintedTotal = stakingMinted + amount;
        if (mintedTotal > totalEmissions) {
            revert TotalAllocationExceeded();
        }

        stakingMinted = mintedTotal;
        _mint(recipient, amount);
    }

    /// @inheritdoc IZKC
    function getSupplyAtEpochStart(uint256 epoch) public pure returns (uint256) {
        return Supply.getSupplyAtEpoch(epoch);
    }

    /// @inheritdoc IZKC
    function getTotalPoVWEmissionsAtEpochStart(uint256 epoch) public returns (uint256) {
        uint256 totalEmissions = getSupplyAtEpochStart(epoch) - INITIAL_SUPPLY;
        return (totalEmissions * POVW_ALLOCATION_BPS) / BASIS_POINTS;
    }

    /// @inheritdoc IZKC
    function getTotalStakingEmissionsAtEpochStart(uint256 epoch) public returns (uint256) {
        uint256 totalEmissions = getSupplyAtEpochStart(epoch) - INITIAL_SUPPLY;
        return (totalEmissions * STAKING_ALLOCATION_BPS) / BASIS_POINTS;
    }

    /// @inheritdoc IZKC
    function getEmissionsForEpoch(uint256 epoch) public returns (uint256) {
        return Supply.getEmissionsForEpoch(epoch);
    }

    /// @inheritdoc IZKC
    function getPoVWEmissionsForEpoch(uint256 epoch) public returns (uint256) {
        uint256 totalEmission = getEmissionsForEpoch(epoch);
        return (totalEmission * POVW_ALLOCATION_BPS) / BASIS_POINTS;
    }

    /// @inheritdoc IZKC
    function getStakingEmissionsForEpoch(uint256 epoch) public returns (uint256) {
        uint256 totalEmission = getEmissionsForEpoch(epoch);
        return (totalEmission * STAKING_ALLOCATION_BPS) / BASIS_POINTS;
    }

    /// @inheritdoc IZKC
    function getCurrentEpoch() public view returns (uint256) {
        return (block.timestamp - deploymentTime) / EPOCH_DURATION;
    }

    /// @inheritdoc IZKC
    function getEpochStartTime(uint256 epoch) public view returns (uint256) {
        return deploymentTime + (epoch * EPOCH_DURATION);
    }

    /// @inheritdoc IZKC
    function getEpochEndTime(uint256 epoch) public view returns (uint256) {
        return getEpochStartTime(epoch + 1) - 1;
    }

    /// @notice Get the total supply during the current epoch
    /// @dev Overrides ERC20 totalSupply to return epoch-based theoretical supply
    function totalSupply() public view override returns (uint256) {
        return getSupplyAtEpochStart(getCurrentEpoch());
    }

    /// @inheritdoc IZKC
    function claimedTotalSupply() public view returns (uint256) {
        return super.totalSupply();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}

