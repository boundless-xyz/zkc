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

    event PoVWRewardsClaimed(address indexed recipient, uint256[] epochs, uint256[] amounts);
    event StakingRewardsClaimed(address indexed recipient, uint256[] epochs, uint256[] amounts);

    error EpochNotEnded(uint256 epoch);
    error EpochAllocationExceeded(uint256 epoch);
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

    function mintPoVWRewardsForRecipient(address recipient, uint256[] calldata amounts, uint256[] calldata epochs) external onlyRole(POVW_MINTER_ROLE) {
        _mintRewardsForRecipient(getPoVWEmissionsForEpoch, epochPoVWMinted, recipient, amounts, epochs);
        emit PoVWRewardsClaimed(recipient, epochs, amounts);
    }

    function mintStakingRewardsForRecipient(address recipient, uint256[] calldata amounts, uint256[] calldata epochs) external onlyRole(STAKING_MINTER_ROLE) {
        _mintRewardsForRecipient(getStakingEmissionsForEpoch, epochStakingMinted, recipient, amounts, epochs);
        emit StakingRewardsClaimed(recipient, epochs, amounts);
    }

    function mintPoVWRewardsForEpoch(uint256 epoch, address[] calldata recipients, uint256[] calldata amounts) external onlyRole(POVW_MINTER_ROLE) {
        _mintRewardsForEpoch(getPoVWEmissionsForEpoch, epochPoVWMinted, epoch, recipients, amounts);
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256[] memory singleEpoch = new uint256[](1);
            uint256[] memory singleAmount = new uint256[](1);
            singleEpoch[0] = epoch;
            singleAmount[0] = amounts[i];
            emit PoVWRewardsClaimed(recipients[i], singleEpoch, singleAmount);
        }
    }

    function mintStakingRewardsForEpoch(uint256 epoch, address[] calldata recipients, uint256[] calldata amounts) external onlyRole(STAKING_MINTER_ROLE) {
        _mintRewardsForEpoch(getStakingEmissionsForEpoch, epochStakingMinted, epoch, recipients, amounts);
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256[] memory singleEpoch = new uint256[](1);
            uint256[] memory singleAmount = new uint256[](1);
            singleEpoch[0] = epoch;
            singleAmount[0] = amounts[i];
            emit StakingRewardsClaimed(recipients[i], singleEpoch, singleAmount);
        }
    }

    function _mintRewardsForRecipient(
        function(uint256) returns (uint256) getEmissionsForEpochFn,
        mapping(uint256 => uint256) storage mintedMapping,
        address recipient, 
        uint256[] calldata amounts, 
        uint256[] calldata epochs
    ) internal {
        if (amounts.length != epochs.length) {
            revert InvalidInputLength();
        }
        
        uint256 currentEpoch = getCurrentEpoch();
        uint256 totalAmount = 0;
        
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 epoch = epochs[i];
            if (epoch >= currentEpoch) {
                revert EpochNotEnded(epoch);
            }
            
            uint256 epochEmissionTotal = getEmissionsForEpochFn(epoch);
            uint256 alreadyMinted = mintedMapping[epoch];
            uint256 mintedTotal = alreadyMinted + amounts[i];
            if (mintedTotal > epochEmissionTotal) {
                revert EpochAllocationExceeded(epoch);
            }
            
            mintedMapping[epoch] = mintedTotal;
            totalAmount += amounts[i];
        }

        _mint(recipient, totalAmount);
    }

    function _mintRewardsForEpoch(
        function(uint256) returns (uint256) getEmissionsForEpochFn,
        mapping(uint256 => uint256) storage mintedMapping,
        uint256 epoch,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) internal {
        if (recipients.length != amounts.length) {
            revert InvalidInputLength();
        }
        
        uint256 currentEpoch = getCurrentEpoch();
        if (epoch >= currentEpoch) {
            revert EpochNotEnded(epoch);
        }
        
        uint256 epochEmissionTotal = getEmissionsForEpochFn(epoch);
        uint256 alreadyMinted = mintedMapping[epoch];
        uint256 totalAmountForEpoch = 0;
        
        // Calculate total amount for this epoch
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmountForEpoch += amounts[i];
        }
        
        uint256 mintedTotal = alreadyMinted + totalAmountForEpoch;
        if (mintedTotal > epochEmissionTotal) {
            revert EpochAllocationExceeded(epoch);
        }
        
        mintedMapping[epoch] = mintedTotal;
        
        // Mint to each recipient
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
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
    function getEpochStartTime(uint256 epoch) external view returns (uint256) {
        return deploymentTime + (epoch * EPOCH_DURATION);
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

