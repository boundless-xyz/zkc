# PoVW emission sunset

Local implementation for November 5, 2026, 00:00 UTC (`1793836800`). Reject PoVW mints at the cutoff and freeze cumulative PoVW allocation at the start of the cutoff epoch, currently 210. Preserve the original passive staking curve, rounding, claims and principal withdrawals. Total supply continues growing through passive staking.

Production changes are confined to `src/ZKC.sol` and the supply getter's `pure` to `view` interface correction. No new storage, initializer, role or transfer restriction. StakingRewards, veZKC and SupplyCalculator remain unchanged. Frozen baseline ZKC is a test fixture.

## Tests

```sh
forge test --offline --match-contract PoVWSunsetTest --fuzz-runs 256
fork-test/run.sh
```

The unit suite passes 16 tests, including 256 fuzz cases. The fork suite passes 4 tests at Ethereum block 26276732. Override `ETHEREUM_RPC_URL` to use another archive provider. Results go to `out/sunset-fork-reports/`.

Fork tests check the pinned chain, block, implementation code hash, actual roles and an existing staking position. They deploy the candidate and execute the real Foundation 3-of-6 Safe using locally impersonated owners. They verify implementation-slot-only writes, unchanged balances/roles, PoVW and staking epoch boundaries, calculator outputs, exact initializer failures and rollback. An existing holder's rewards and withdrawals are compared against the original implementation; a withdrawal pending before upgrade also completes. No transaction is broadcast.

The fixed historical fork is a reproducible rehearsal. Final production deployment bytecode, addresses and transaction payloads still require verification before signing.
