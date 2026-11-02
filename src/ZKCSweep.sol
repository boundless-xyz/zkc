// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ZKCFreeze} from "./ZKCFreeze.sol";

/// @title ZKCSweep - Temporary ZKC implementation moving the frozen balance to a fixed recipient
/// @notice Inherits ZKCFreeze unchanged and adds a single admin-gated function; declares no new storage.
/// @dev Intended to be live for the duration of a single Safe transaction:
///      1. upgradeToAndCall(ZKCSweep, sweep())
///      2. upgradeToAndCall(<ZKCFreeze implementation>, "")
contract ZKCSweep is ZKCFreeze {
    /// @notice Recipient of the swept balance
    address public constant SWEEP_RECIPIENT = 0xD45e232819045d9D34fd107d19b594170515580E;

    /// @notice balanceOf(FROZEN) at Ethereum block 26308038
    uint256 public constant SWEEP_AMOUNT = 19_655_868_682776268123875006;

    /// @notice Move SWEEP_AMOUNT from FROZEN to SWEEP_RECIPIENT
    /// @dev Calls ERC20's _update directly to skip the freeze check. The resulting balance writes and
    ///      Transfer(FROZEN, SWEEP_RECIPIENT, SWEEP_AMOUNT) event are identical to FROZEN calling transfer().
    function sweep() external onlyRole(ADMIN_ROLE) {
        ERC20Upgradeable._update(FROZEN, SWEEP_RECIPIENT, SWEEP_AMOUNT);
    }
}
