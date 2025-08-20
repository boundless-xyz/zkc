// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

/// @title Clock Component
/// @notice Shared base for IERC6372 clock functionality and timepoint validation
/// @dev This component provides clock functions and ERC5805-style future lookup protection
abstract contract Clock is IERC6372 {

    // Custom error for ERC5805-style future lookup protection
    error ERC5805FutureLookup(uint256 timepoint, uint48 clock);

    /// @inheritdoc IERC6372
    function clock() public view virtual override returns (uint48) {
        return uint48(block.timestamp); 
    }

    function CLOCK_MODE() public pure virtual override returns (string memory) {
        return "mode=timestamp";
    }

    /// @dev Internal function to validate timepoint for historical queries
    ///      Reverts if timepoint is not strictly in the past
    function _requirePastTimepoint(uint256 timepoint) internal view {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
    }
}