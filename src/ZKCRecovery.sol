// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ZKC} from "./ZKC.sol";

/// @title ZKCRecovery - Temporary ZKC implementation to return tokens sent to the ZKC contract itself
/// @notice Inherits ZKC unchanged and adds a single admin-gated function; declares no new storage.
/// @dev Intended to be live for the duration of a single Safe transaction:
///      1. upgradeToAndCall(ZKCRecovery, recoverSelfTransfer(...))
///      2. upgradeToAndCall(<previous ZKC implementation>, "")
contract ZKCRecovery is ZKC {
    /// @notice Transfer ZKC held by the ZKC contract (at the proxy address) to `to`
    /// @dev Uses a real ERC20 transfer so a standard Transfer event is emitted for indexers
    /// @param to Recipient of the recovered tokens
    /// @param amount Amount of tokens to recover
    function recoverSelfTransfer(address to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        _transfer(address(this), to, amount);
    }
}
