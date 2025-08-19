// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRewards {
    function getRewards(address account) external view returns (uint256);
    function getPastRewards(address account, uint256 timepoint) external view returns (uint256);
    function getTotalRewards() external view returns (uint256);
    function getPastTotalRewards(uint256 timepoint) external view returns (uint256);
}

/**
interface IRewards {
    function getStakingRewards(address account) external view returns (uint256);
    function getPastStakingRewards(address account, uint256 timepoint) external view returns (uint256);
    function getTotalStakingRewards() external view returns (uint256);
    function getPastTotalStakingRewards(uint256 timepoint) external view returns (uint256);

    function getPoVWRewardCap(address account) external view returns (uint256);
    function getPastPoVWRewardCap(address account, uint256 timepoint) external view returns (uint256);
} */