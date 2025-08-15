// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ZKC} from "../ZKC.sol";
import {IRewards} from "../interfaces/IRewards.sol";

/**
 * @title StakingRewards
 * @notice Contract for distributing staking rewards based on veZKC staking positions
 * @dev Users can claim rewards for specific epochs based on their staking value
 */
contract StakingRewards is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    
    /// @notice ZKC token contract
    ZKC public zkc;
    
    /// @notice veZKC rewards interface for getting staking positions
    IRewards public veZKC;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address _zkc,
        address _veZKC,
        address _admin
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        zkc = ZKC(_zkc);
        veZKC = IRewards(_veZKC);
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }
    
    /**
     * @notice Claim rewards for a specific epoch
     * @param epoch The epoch to claim rewards for
     * @return amount The amount of rewards claimed
     */
    function claimRewards(uint256 epoch) 
        external 
        nonReentrant 
        returns (uint256 amount) 
    {
        revert("Not implemented");
    }
    
    /**
     * @notice Claim rewards for multiple epochs in a single transaction
     * @param epochs Array of epochs to claim rewards for
     * @return totalAmount Total amount of rewards claimed across all epochs
     */
    function batchClaimRewards(uint256[] calldata epochs) 
        external 
        nonReentrant 
        returns (uint256 totalAmount) 
    {
        revert("Not implemented");
    }
    
    /**
     * @notice Calculate the rewards a user is owed for a specific epoch
     * @param user The user address
     * @param epoch The epoch to calculate rewards for
     * @return amount The amount of rewards owed
     */
    function calculateRewardsForEpoch(address user, uint256 epoch) 
        external 
        view 
        returns (uint256 amount) 
    {
        // TODO: Implement reward calculation logic
        // 1. Get user's staking value for this epoch via IRewards interface
        // 2. Calculate proportional share of epoch's staking allocation
        // 3. Return calculated amount
        
        revert("Not implemented");
    }
    
    /**
     * @notice Check if a user has claimed rewards for a specific epoch
     * @param user The user address
     * @param epoch The epoch to check
     * @return claimed Whether rewards have been claimed
     */
    function hasUserClaimedRewards(address user, uint256 epoch) 
        external 
        view 
        returns (bool claimed) 
    {
        revert("Not implemented");
    }
    
    /**
     * @notice Get the current epoch from the ZKC contract
     * @return currentEpoch The current epoch number
     */
    function getCurrentEpoch() external view returns (uint256 currentEpoch) {
        return zkc.getCurrentEpoch();
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
