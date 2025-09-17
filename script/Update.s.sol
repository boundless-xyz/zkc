// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {console2} from "forge-std/Script.sol";
import {CirculatingZKC} from "../src/circulating/CirculatingZKC.sol";
import {ConfigLoader, DeploymentConfig} from "./Config.s.sol";
import {BaseDeployment} from "./BaseDeployment.s.sol";

/**
 * Sample Usage for updating CirculatingZKC unlocked value:
 *
 * # Direct execution:
 * export CHAIN_KEY="anvil"
 * export NEW_UNLOCKED="750000000000000000000000000"  # 750M tokens
 *
 * forge script script/Update.s.sol:UpdateCirculatingUnlocked \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast \
 *     --rpc-url http://127.0.0.1:8545
 *
 * # Gnosis Safe execution (print call data only):
 * export CHAIN_KEY="anvil"
 * export NEW_UNLOCKED="750000000000000000000000000"  # 750M tokens
 * export GNOSIS_EXECUTE=true
 *
 * forge script script/Update.s.sol:UpdateCirculatingUnlocked \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --rpc-url http://127.0.0.1:8545
 */
contract UpdateCirculatingUnlocked is BaseDeployment {
    function setUp() public {}

    function run() public {
        (DeploymentConfig memory config, string memory deploymentKey) = ConfigLoader.loadDeploymentConfig(vm);
        require(config.circulatingZKC != address(0), "CirculatingZKC address not set in deployment.toml");

        // Get new unlocked value from environment
        uint256 newUnlocked = vm.envUint("NEW_UNLOCKED");
        require(newUnlocked > 0, "NEW_UNLOCKED must be greater than 0");

        // Check for Gnosis Safe execution mode
        bool gnosisExecute = vm.envOr("GNOSIS_EXECUTE", false);

        // Get the contract instance
        CirculatingZKC circulatingContract = CirculatingZKC(config.circulatingZKC);

        // Get current values for logging
        uint256 currentUnlocked = circulatingContract.unlocked();
        uint256 currentCirculatingSupply = circulatingContract.circulatingSupply();

        console2.log("================================================");
        console2.log("Current unlocked amount: ", currentUnlocked);
        console2.log("Current unlocked amount (in tokens): ", currentUnlocked / 10 ** 18);
        console2.log("Current circulating supply: ", currentCirculatingSupply);
        console2.log("Current circulating supply (in tokens): ", currentCirculatingSupply / 10 ** 18);
        console2.log("================================================");

        if (gnosisExecute) {
            // Print Gnosis Safe transaction info for manual execution
            _printGnosisSafeInfo(config.circulatingZKC, newUnlocked);

            // Calculate expected new circulating supply for display
            uint256 expectedNewCirculatingSupply = currentCirculatingSupply - currentUnlocked + newUnlocked;

            console2.log("Expected after update:");
            console2.log("New unlocked amount: ", newUnlocked);
            console2.log("New unlocked amount (in tokens): ", newUnlocked / 10 ** 18);
            console2.log("New circulating supply: ", expectedNewCirculatingSupply);
            console2.log("New circulating supply (in tokens): ", expectedNewCirculatingSupply / 10 ** 18);
            console2.log("================================================");
        } else {
            vm.startBroadcast();

            // Update the unlocked value
            circulatingContract.updateUnlockedValue(newUnlocked);

            // Get updated values
            uint256 updatedUnlocked = circulatingContract.unlocked();
            uint256 updatedCirculatingSupply = circulatingContract.circulatingSupply();

            vm.stopBroadcast();

            console2.log("Updated unlocked value!");
            console2.log("================================================");
            console2.log("New unlocked amount: ", updatedUnlocked);
            console2.log("New unlocked amount (in tokens): ", updatedUnlocked / 10 ** 18);
            console2.log("New circulating supply: ", updatedCirculatingSupply);
            console2.log("New circulating supply (in tokens): ", updatedCirculatingSupply / 10 ** 18);
            console2.log("================================================");
            console2.log("Change in unlocked: ", newUnlocked > currentUnlocked ? "+" : "-");
            if (newUnlocked > currentUnlocked) {
                console2.log("  Amount increased: ", (newUnlocked - currentUnlocked) / 10 ** 18, " tokens");
            } else {
                console2.log("  Amount decreased: ", (currentUnlocked - newUnlocked) / 10 ** 18, " tokens");
            }
        }
    }

    /// @notice Print Gnosis Safe transaction information for manual updates
    /// @param targetAddress The CirculatingZKC contract address (target for Gnosis Safe)
    /// @param newUnlocked The new unlocked value to set
    function _printGnosisSafeInfo(address targetAddress, uint256 newUnlocked) internal pure {
        console2.log("================================");
        console2.log("================================");
        console2.log("=== GNOSIS SAFE UPDATE INFO ===");
        console2.log("Target Address (To): ", targetAddress);
        console2.log("Function: updateUnlockedValue(uint256)");
        console2.log("New Unlocked Value: ", newUnlocked);
        console2.log("New Unlocked Value (in tokens): ", newUnlocked / 10 ** 18);

        bytes memory callData = abi.encodeWithSignature("updateUnlockedValue(uint256)", newUnlocked);
        console2.log("");
        console2.log("Calldata:");
        console2.logBytes(callData);
        console2.log("");
        console2.log("Expected Events on Successful Execution:");
        console2.log("1. UnlockedValueUpdated(uint256 oldValue, uint256 newValue)");
        console2.log("   - newValue: ", newUnlocked);
        console2.log("================================");
    }
}