// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ZKC is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    address public initialMinter1;
    address public initialMinter2;
    uint256 public initialMinter1Remaining;
    uint256 public initialMinter2Remaining;

    bytes32 public immutable ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public immutable MINTER_ROLE = keccak256("MINTER_ROLE");

    // Inflation constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;  // 1 billion ZKC
    uint256 public constant INITIAL_INFLATION_RATE = 700;             // 7.00% in basis points
    uint256 public constant FINAL_INFLATION_RATE = 300;               // 3.00% in basis points
    uint256 public constant INFLATION_STEP = 50;                      // 0.50% reduction per year
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant EPOCH_DURATION = 2 days;
    uint256 public constant EPOCHS_PER_YEAR = 182;                    // Approximately 365/2
    uint256 public constant POVW_ALLOCATION = 75;                     // 75% for PoVW rewards
    uint256 public constant STAKING_ALLOCATION = 25;                  // 25% for staking rewards

    // New roles for inflation minting
    bytes32 public immutable POVW_MINTER_ROLE = keccak256("POVW_MINTER_ROLE");
    bytes32 public immutable STAKING_MINTER_ROLE = keccak256("STAKING_MINTER_ROLE");

    // Inflation tracking storage
    uint256 public deploymentTime;
    mapping(uint256 => uint256) public epochPoVWMinted;      // Track PoVW minting per epoch
    mapping(uint256 => uint256) public epochStakingMinted;   // Track staking minting per epoch

    event PoVWRewardMinted(uint256 indexed epoch, address indexed recipient, uint256 amount);
    event StakingRewardMinted(uint256 indexed epoch, address indexed recipient, uint256 amount);

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

    function mintPoVWReward(address to, uint256 amount, uint256 epoch) external onlyRole(POVW_MINTER_ROLE) {
        uint256 totalEpochInflation = getEpochEmissionAmount(epoch);
        uint256 povwAllocation = (totalEpochInflation * POVW_ALLOCATION) / 100;
        _mintReward(to, amount, epoch, povwAllocation, epochPoVWMinted);
        emit PoVWRewardMinted(epoch, to, amount);
    }

    function mintStakingReward(address to, uint256 amount, uint256 epoch) external onlyRole(STAKING_MINTER_ROLE) {
        uint256 totalEpochInflation = getEpochEmissionAmount(epoch);
        uint256 stakingAllocation = (totalEpochInflation * STAKING_ALLOCATION) / 100;
        _mintReward(to, amount, epoch, stakingAllocation, epochStakingMinted);
        emit StakingRewardMinted(epoch, to, amount);
    }

    function _mintReward(
        address to, 
        uint256 amount, 
        uint256 epoch, 
        uint256 allocation, 
        mapping(uint256 => uint256) storage mintedMapping
    ) internal {
        require(epoch > 0, "Invalid epoch");
        
        // Initialize deployment time if first use
        if (deploymentTime == 0) {
            deploymentTime = block.timestamp - (epoch * EPOCH_DURATION);
        }
        
        uint256 currentEpoch = getCurrentEpoch();
        require(epoch <= currentEpoch, "Invalid epoch");
        
        // Check that we haven't exceeded the allocation
        uint256 alreadyMinted = mintedMapping[epoch];
        require(alreadyMinted + amount <= allocation, "Exceeds allocation for epoch");
        
        // Update tracking
        mintedMapping[epoch] = alreadyMinted + amount;
        
        // Mint the tokens
        _mint(to, amount);
    }

    function getCurrentEpoch() public view returns (uint256) {
        if (deploymentTime == 0) return 0;
        return (block.timestamp - deploymentTime) / EPOCH_DURATION;
    }

    function getAnnualInflationRate(uint256 epoch) public pure returns (uint256) {
        // Calculate completed years
        uint256 yearsCompleted = epoch / EPOCHS_PER_YEAR;
        
        // Calculate rate: 7% - (0.5% × years), minimum 3%
        uint256 reduction = yearsCompleted * INFLATION_STEP;
        
        if (INITIAL_INFLATION_RATE <= reduction + FINAL_INFLATION_RATE) {
            return FINAL_INFLATION_RATE;
        }
        
        return INITIAL_INFLATION_RATE - reduction;
    }

    // TODO: Use Fixed Point representation + pow?, or optimize with precomputed values for the supply at each epoch?
    function getSupplyAtEpoch(uint256 epoch) public pure returns (uint256) {
        if (epoch == 0) return INITIAL_SUPPLY;
        
        uint256 supply = INITIAL_SUPPLY;
        
        for (uint256 e = 1; e <= epoch; e++) {
            // Get the annual rate for this epoch
            uint256 annualRate = getAnnualInflationRate(e);
            
            // Convert to per-epoch rate: annual_rate / epochs_per_year
            // Using higher precision: (annualRate * 1000) / (EPOCHS_PER_YEAR * 1000)
            uint256 epochRate = annualRate * 1000 / EPOCHS_PER_YEAR;
            
            // Apply inflation: new = old * (1 + rate/BASIS_POINTS/1000)
            uint256 inflation = supply * epochRate / BASIS_POINTS / 1000;
            supply = supply + inflation;
        }
        
        return supply;
    }

    function getEpochEmissionAmount(uint256 epoch) public pure returns (uint256) {
        if (epoch == 0) return 0;
        
        uint256 supplyAtEpoch = getSupplyAtEpoch(epoch);
        uint256 supplyAtPrevEpoch = getSupplyAtEpoch(epoch - 1);
        
        return supplyAtEpoch - supplyAtPrevEpoch;
    }

    // View functions for monitoring allocations
    function getPoVWAllocationForEpoch(uint256 epoch) external pure returns (uint256) {
        uint256 totalInflation = getEpochEmissionAmount(epoch);
        return (totalInflation * POVW_ALLOCATION) / 100;
    }

    function getStakingAllocationForEpoch(uint256 epoch) external pure returns (uint256) {
        uint256 totalInflation = getEpochEmissionAmount(epoch);
        return (totalInflation * STAKING_ALLOCATION) / 100;
    }

    function getPoVWRemainingForEpoch(uint256 epoch) external view returns (uint256) {
        uint256 allocation = this.getPoVWAllocationForEpoch(epoch);
        uint256 minted = epochPoVWMinted[epoch];
        return allocation > minted ? allocation - minted : 0;
    }

    function getStakingRemainingForEpoch(uint256 epoch) external view returns (uint256) {
        uint256 allocation = this.getStakingAllocationForEpoch(epoch);
        uint256 minted = epochStakingMinted[epoch];
        return allocation > minted ? allocation - minted : 0;
    }

    function getTotalEpochInflation(uint256 epoch) external pure returns (uint256) {
        return getEpochEmissionAmount(epoch);
    }

    function getEpochStartTime(uint256 epoch) external view returns (uint256) {
        return deploymentTime + (epoch * EPOCH_DURATION);
    }
}
