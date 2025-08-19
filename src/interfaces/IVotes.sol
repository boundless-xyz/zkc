// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotes as OZIVotes} from "@openzeppelin/contracts/interfaces/IERC5805.sol";

/**
 * @title IVotes
 * @notice Empty interface that extends OpenZeppelin's IVotes interface
 * @dev This allows us to extend the standard IVotes interface in the future if needed
 */
interface IVotes is OZIVotes {
    // Custom errors
    error NotImplemented();
    
    // This interface is intentionally empty
    // It simply extends OpenZeppelin's IVotes interface
}