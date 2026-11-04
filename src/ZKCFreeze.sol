// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ZKC} from "./ZKC.sol";

/// @title ZKCFreeze - ZKC with outgoing transfers from a single address frozen
/// @notice Inherits ZKC unchanged; declares no new storage. Reversal requires an admin upgrade.
contract ZKCFreeze is ZKC {
    address public constant FROZEN = 0xA97bF7836F8A08F9Ed91D41453D371493FAE8d10;

    error AccountFrozen(address account);

    /// @dev Blocks every debit from FROZEN (transfer, transferFrom, burn, burnFrom). Mints and incoming transfers pass.
    function _update(address from, address to, uint256 value) internal override {
        if (from == FROZEN) revert AccountFrozen(from);
        super._update(from, to, value);
    }
}
