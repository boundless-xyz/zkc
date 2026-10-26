// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {ZKC} from "../../src/ZKC.sol";
import {RuntimeCheck} from "./RuntimeCheck.sol";
import {SunsetTransaction} from "./SunsetTransaction.sol";

library ZKCSunset {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant PROXY = 0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555;
    address internal constant SAFE = 0x3886eEaf95AA2bDDdf0C924925e290291f70447F;
    bytes32 private constant SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function prepare(address requested)
        internal
        returns (SunsetTransaction.Transaction memory transaction, address candidate)
    {
        require(block.chainid == 1, "Ethereum required");
        address baseline = address(uint160(uint256(VM.load(PROXY, SLOT))));
        require(
            baseline == 0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98
                && baseline.codehash == 0x809103882fcb7d3a50c452a7db932916ec00c50abacbb3452508085a6aa79529,
            "unexpected ZKC baseline"
        );
        require(ZKC(PROXY).hasRole(ZKC(PROXY).ADMIN_ROLE(), SAFE), "unexpected ZKC admin");
        // Check before CREATE, so its predicted address cannot masquerade as a deployed candidate.
        if (requested != address(0)) RuntimeCheck.requireExisting(requested);
        address local = address(new ZKC());
        candidate = requested == address(0) ? local : requested;
        RuntimeCheck.check(
            local,
            candidate,
            string.concat(VM.projectRoot(), "/", VM.envString("SUNSET_ARTIFACT_ROOT"), "/ZKC.sol/ZKC.json")
        );
        return (SunsetTransaction.single(SAFE, PROXY, candidate), candidate);
    }
}
