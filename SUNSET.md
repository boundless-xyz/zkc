# PoVW emission sunset

Local implementation for November 5, 2026, 00:00 UTC (`1793836800`). Reject PoVW mints at the cutoff and freeze cumulative PoVW allocation at the start of the cutoff epoch, currently 210. Preserve the original passive staking curve, rounding, claims and principal withdrawals. Total supply continues growing through passive staking.

Production changes are confined to `src/ZKC.sol` and the supply getter's `pure` to `view` interface correction. No new storage, initializer, role or transfer restriction. StakingRewards, veZKC and SupplyCalculator remain unchanged. Frozen baseline ZKC is a test fixture.

## Tests

```sh
forge test --offline --match-contract ZKCSunsetTest --fuzz-runs 256
fork-test/run.sh
```

The unit suite passes 16 tests, including 256 fuzz cases. The fork suite passes 6 tests at Ethereum block 26276732. Override `ETHEREUM_RPC_URL` to use another archive provider. Results go to `out/sunset-fork-reports/`.

Fork tests check the pinned chain, block, implementation code hash, actual roles and an existing staking position. They deploy the candidate and execute the real Foundation 3-of-6 Safe using locally impersonated owners. They verify implementation-slot-only writes, unchanged balances/roles, PoVW and staking epoch boundaries, calculator outputs, exact initializer failures and rollback. An existing holder's rewards and withdrawals are compared against the original implementation; a withdrawal pending before upgrade also completes. No transaction is broadcast.

The fixed historical fork is a reproducible rehearsal. Final production deployment bytecode, addresses and transaction payloads still require verification before signing.

## Prepare the exact Safe transaction

Use the wrappers below; they set the required artifact path and build profile. The printer requires an implementation already deployed on the selected network. It checks its complete runtime against this build, including constructor dependencies, allowing only self-address immutable differences. Tests and printer share the same calldata builder. The scripts never broadcast; reference implementations exist only in the local script VM.

```sh
SUNSET_IMPL=<zkc-implementation> script/sunset/prepare.sh
SUNSET_IMPL=<zkc-implementation> SUNSET_BLOCK_NUMBER=<block-after-deployment> fork-test/run.sh
```

This printer supplies the ZKC input to the market repo's `contracts/scripts/sunset/prepare-ethereum.sh`. That command validates both repos at one block and emits one atomic Foundation Safe transaction containing Accounting, Mint and ZKC. Sign the combined output, not this intermediate transaction.

Each command writes `transaction.json` with all Safe fields, current nonce and transaction hash, plus `simulation.json`. The preflight uses read-only `eth_call` at the recorded block and an explicit threshold override from 3 to 1. The fork tests separately execute the real 3-of-6 threshold. The RPC must support historical state and state overrides.

The helper generates a Tenderly draft link locally. It does not submit a Tenderly simulation. If the link omits long calldata, paste `execTransactionData` from `simulation.json` into Raw input data. Verify the network and recorded block before simulating. No private key is required.

Preflight guard tests use a mocked transport: `python3 -m unittest discover -s script/sunset -p 'test_*.py'`. The local Anvil workflow separately checks real calldata encoding and Safe execution.
