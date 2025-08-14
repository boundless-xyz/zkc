// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRewards {
    function getRewardPower(address account) external view returns (uint256);
    function getPastRewardPower(address account, uint256 timepoint) external view returns (uint256);
    function getTotalRewardPower() external view returns (uint256);
    function getPastTotalRewardPower(uint256 timepoint) external view returns (uint256);
}
