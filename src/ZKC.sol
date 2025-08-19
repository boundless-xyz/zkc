// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Supply} from "./libraries/Supply.sol";

contract ZKC is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    address public initialMinter1;
    address public initialMinter2;
    uint256 public initialMinter1Remaining;
    uint256 public initialMinter2Remaining;

    bytes32 public immutable ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public immutable MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18; 

    // Basis points used for inflation calculations and minting allocations.
    uint256 public constant BASIS_POINTS = 10000;

    // Every epoch lasts 2 days
    uint256 public constant EPOCH_DURATION = 2 days;
    uint256 public constant EPOCHS_PER_YEAR = 182;                   
    // 75% of emissions per epoch are allocated to PoVW rewards
    uint256 public constant POVW_ALLOCATION_BPS = 7500;                    
    // 25% of emissions per epoch are allocated to staking rewards
    uint256 public constant STAKING_ALLOCATION_BPS = 2500;   

    bytes32 public immutable POVW_MINTER_ROLE = keccak256("POVW_MINTER_ROLE");
    bytes32 public immutable STAKING_MINTER_ROLE = keccak256("STAKING_MINTER_ROLE");

    uint256 public deploymentTime;
    mapping(uint256 => uint256) public epochPoVWMinted;      // Track PoVW minting per epoch
    mapping(uint256 => uint256) public epochStakingMinted;   // Track staking minting per epoch
    uint256 public poVWMinted;                              // Track total PoVW minting
    uint256 public stakingMinted;                          // Track total staking minting

    event PoVWRewardsClaimed(address indexed recipient, uint256 amount);
    event StakingRewardsClaimed(address indexed recipient, uint256 amount);

    error EpochNotEnded(uint256 epoch);
    error EpochAllocationExceeded(uint256 epoch);
    error TotalAllocationExceeded();
    error InvalidInputLength();

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

    function mintPoVWRewardsForRecipient(address recipient, uint256 amount) external onlyRole(POVW_MINTER_ROLE) {
        _mintRewardsForRecipient(getTotalPoVWEmissions, poVWMinted, recipient, amount);
        emit PoVWRewardsClaimed(recipient, amount);
    }

    function mintStakingRewardsForRecipient(address recipient, uint256 amount) external onlyRole(STAKING_MINTER_ROLE) {
        _mintRewardsForRecipient(getTotalStakingEmissions, stakingMinted, recipient, amount);
        emit StakingRewardsClaimed(recipient, amount);
    }

    function _mintRewardsForRecipient(
        function(uint256) returns (uint256) getTotalEmissionsFn,
        uint256 storage alreadyMinted,
        address recipient, 
        uint256 amount
    ) internal {
        uint256 totalEmissions = getTotalEmissionsFn(getCurrentEpoch() - 1);
        uint256 mintedTotal = alreadyMinted + amount;
        if (mintedTotal > totalEmissions) {
            revert TotalAllocationExceeded();
        }

        alreadyMinted = mintedTotal;
        _mint(recipient, amount);
    }

    // Returns the supply at the start of the provided epoch.
    // ZKC is emitted at the end of each epoch, this excludes the rewards that will be
    // generated as part of the work within this epoch.
    function getSupplyAtEpoch(uint256 epoch) public pure returns (uint256) {
        return Supply.getSupplyAtEpoch(epoch);
    }

    // Returns the amount of ZKC that will be emitted at the end of the provided epoch.
    // Includes both rewards for PoVW and for active staking.
    function getEmissionsForEpoch(uint256 epoch) public returns (uint256) {
        return Supply.getEmissionsForEpoch(epoch);
    }

    // Returns the amount of ZKC that will be emitted for PoVW rewards at the end of the provided epoch.
    function getPoVWEmissionsForEpoch(uint256 epoch) public returns (uint256) {
        uint256 totalEmission = getEmissionsForEpoch(epoch);
        return (totalEmission * POVW_ALLOCATION_BPS) / BASIS_POINTS;
    }

    // Returns the amount of ZKC that will have been emitted for PoVW rewards since the start of ZKC
    // to the end of the provided epoch (so includes emissions from the provided epoch).
    function getTotalPoVWEmissions(uint256 epoch) public returns (uint256) {
        uint256 totalEmissions = getSupplyAtEpoch(epoch + 1) - INITIAL_SUPPLY;
        return (totalEmissions * POVW_ALLOCATION_BPS) / BASIS_POINTS;
    }

    // Returns the total amount of ZKC that will have been emitted for staking rewards 
    // from the start of ZKC to the end of the provided epoch (so includes emissions from the provided epoch).
    function getTotalStakingEmissions(uint256 epoch) public returns (uint256) {
        uint256 totalEmissions = getSupplyAtEpoch(epoch + 1) - INITIAL_SUPPLY;
        return (totalEmissions * STAKING_ALLOCATION_BPS) / BASIS_POINTS;
    }

    // Returns the amount of ZKC that will be emitted for staking rewards at the end of the provided epoch.
    function getStakingEmissionsForEpoch(uint256 epoch) public returns (uint256) {
        uint256 totalEmission = getEmissionsForEpoch(epoch);
        return (totalEmission * STAKING_ALLOCATION_BPS) / BASIS_POINTS;
    }

    // Returns the amount of ZKC that can still be minted (i.e. is unclaimed) for PoVW rewards at the end of the provided epoch.
    function getPoVWUnclaimedForEpoch(uint256 epoch) public returns (uint256) {
        uint256 allocation = getPoVWEmissionsForEpoch(epoch);
        uint256 minted = epochPoVWMinted[epoch];
        return allocation - minted;
    }

    // Returns the amount of ZKC that can still be minted (i.e. is unclaimed) for staking rewards at the end of the provided epoch.
    function getStakingUnclaimedForEpoch(uint256 epoch) public returns (uint256) {
        uint256 allocation = getStakingEmissionsForEpoch(epoch);
        uint256 minted = epochStakingMinted[epoch];
        return allocation - minted;
    }

    function getCurrentEpoch() public view returns (uint256) {
        return (block.timestamp - deploymentTime) / EPOCH_DURATION;
    }

    // Returns the start time of the provided epoch.
    function getEpochStartTime(uint256 epoch) public view returns (uint256) {
        return deploymentTime + (epoch * EPOCH_DURATION);
    }

    // Returns the end time of the provided epoch. Meaning the final timestamp
    // at which the epoch is "active". After this timestamp is finalized, the 
    // state at this timestamp represents the final state of the epoch.
    function getEpochEndTime(uint256 epoch) public view returns (uint256) {
        return getEpochStartTime(epoch + 1) - 1;
    }

    /**
     * @notice This is the total supply during the current epoch.
     * @dev This is the total supply during the current epoch. Emissions for the epoch
     * occur at the end of the epoch.
     * @return The total supply during the current epoch
     */
    function totalSupply() public view override returns (uint256) {
        return getSupplyAtEpoch(getCurrentEpoch());
    }

    /**
     * @notice Returns the actual claimed total supply
     * @dev This is what has actually been minted to an account and thus claimed.
     * @return The total amount of tokens that have been claimed
     */
    function claimedTotalSupply() public view returns (uint256) {
        return super.totalSupply();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}

