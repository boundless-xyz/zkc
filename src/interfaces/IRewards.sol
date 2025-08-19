// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRewards {
    function getRewards(address account) external view returns (uint256);
    function getPastRewards(address account, uint256 timepoint) external view returns (uint256);
    function getTotalRewards() external view returns (uint256);
    function getPastTotalRewards(uint256 timepoint) external view returns (uint256);
    
    // Reward delegation functions
    function rewardDelegates(address account) external view returns (address);
    function delegateRewards(address rewardCollector) external;
    function delegateRewardsBySig(
        address rewardCollector,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    
    // Events
    event RewardDelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
}
