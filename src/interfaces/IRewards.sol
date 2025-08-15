// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRewards {
    function getRewards(address account) external view returns (uint256);
    function getPastRewards(address account, uint256 timepoint) external view returns (uint256);
    function getTotalRewards() external view returns (uint256);
    function getPastTotalRewards(uint256 timepoint) external view returns (uint256);
}
