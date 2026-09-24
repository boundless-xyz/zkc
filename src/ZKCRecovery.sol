// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ZKC} from "./ZKC.sol";

/// @title ZKCRecovery - Temporary ZKC implementation to return tokens sent to the ZKC contract itself
/// @notice Inherits ZKC unchanged and adds a single admin-gated function; declares no new storage.
/// @dev Intended to be live for the duration of a single Safe transaction:
///      1. upgradeToAndCall(ZKCRecovery, recoverSelfTransfer())
///      2. upgradeToAndCall(<previous ZKC implementation>, "")
contract ZKCRecovery is ZKC {
    /// @notice Sender of tx 0xb4d0876ba9c719d56daae809c51f6553a5936f87674f2ed588e6c32d860997f3
    address public constant RECOVERY_RECIPIENT = 0x51DEf0949495956a5a177087C930AbB7171104c0;

    /// @notice Amount transferred to the ZKC contract in that tx
    uint256 public constant RECOVERY_AMOUNT = 1_290_546e18;

    /// @notice Return RECOVERY_AMOUNT of ZKC held by the ZKC contract to RECOVERY_RECIPIENT
    /// @dev Uses a real ERC20 transfer so a standard Transfer event is emitted for indexers
    function recoverSelfTransfer() external onlyRole(ADMIN_ROLE) {
        _transfer(address(this), RECOVERY_RECIPIENT, RECOVERY_AMOUNT);
    }
}
