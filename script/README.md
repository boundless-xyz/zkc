# ZKC Scripts

## Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Python 3 with `tomlkit`: `pip install tomlkit`
- [yq](https://github.com/mikefarah/yq): `brew install yq`

## Setup

1. **Configure secrets** (copy template and fill in your values):
```bash
cp deployment_secrets.toml deployment_secrets.toml
# Edit with your RPC URLs, private keys, API keys
```

2. **Update admin addresses** in `deployment.toml` for each network

## Deployment

### Deploy ZKC Token

```bash
# Set environment variables
export CHAIN_KEY="anvil"  # anvil, ethereum-mainnet, ethereum-sepolia
export INITIAL_MINTER_1="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
export INITIAL_MINTER_2="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
export TOTAL_INITIAL_SUPPLY="1000000000000000000000000000"
export INITIAL_MINTER_1_AMOUNT="550000000000000000000000000"
export INITIAL_MINTER_2_AMOUNT="450000000000000000000000000"
export SALT="0x0000000000000000000000000000000000000000000000000000000000000001"

# Deploy
./script/manage deploy-zkc --broadcast
```

### Deploy veZKC (requires ZKC first)

```bash
export CHAIN_KEY="anvil"
export SALT="0x0000000000000000000000000000000000000000000000000000000000000001"

./script/manage deploy-vezkc --broadcast
```

## Upgrades

```bash
# Upgrade ZKC
CHAIN_KEY=ethereum-mainnet ./script/manage upgrade-zkc --broadcast --verify

# Upgrade veZKC  
CHAIN_KEY=ethereum-mainnet ./script/manage upgrade-vezkc --broadcast --verify

# Upgrade all contracts
CHAIN_KEY=ethereum-mainnet ./script/manage upgrade-all --broadcast --verify
```

## Production Deployment (Fireblocks)

```bash
# Deploy with Fireblocks signing
CHAIN_KEY=ethereum-mainnet ./script/manage deploy-zkc --fireblocks --broadcast --verify

# Upgrade with Fireblocks signing
CHAIN_KEY=ethereum-mainnet ./script/manage upgrade-zkc --fireblocks --broadcast --verify
```

## Files

- `deployment.toml`: Contract addresses (auto-updated)
- `deployment_secrets.toml`: RPC URLs (gitignored)

## Examples

```bash
# Local development
CHAIN_KEY=anvil ./script/manage deploy-zkc --broadcast

# Testnet
CHAIN_KEY=ethereum-sepolia ./script/manage deploy-zkc --broadcast --verify

# Mainnet production
CHAIN_KEY=ethereum-mainnet ./script/manage deploy-zkc --fireblocks --broadcast --verify
```

## Sunset verification

Use this branch with the sibling `market` checkout on `codex/protocol-sunset`.
The shared [fork runbook](../../market/contracts/fork-test/README.md) covers setup,
unit tests, OpenZeppelin validation and staging/production Anvil rehearsals. It rebuilds
ZKC with solc 0.8.26 targeting Cancun, matching the reviewed candidate. Passive staking
rewards and withdrawals remain available; only PoVW minting and future allocation stop.
No veZKC, StakingRewards or SupplyCalculator upgrade is part of the sunset.

The existing recovery fork suite requires Ethereum block **26085537**. Recovery happened
at 26085538, so running against latest state cannot reproduce its original balance assumption.
From `zkc/`, after the shared setup, run this in a Bash shell:

```bash
set -euo pipefail
mkdir -p out
recovery_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
anvil --host 127.0.0.1 --port "$recovery_port" --fork-url "${ETHEREUM_RPC_URL:-https://eth.drpc.org}" --fork-block-number 26085537 --silent >out/recovery-anvil.log 2>&1 &
recovery_pid=$!
trap 'kill "$recovery_pid" 2>/dev/null || true' EXIT
for attempt in {1..60}; do
  kill -0 "$recovery_pid"
  if cast chain-id --rpc-url "http://127.0.0.1:$recovery_port" >/dev/null 2>&1; then break; fi
  sleep 1
done
MAINNET_RPC_URL="http://127.0.0.1:$recovery_port" ZKC_RECOVERY_IMPL=0x0000000000000000000000000000000000000000 FOUNDRY_FFI=false forge test --offline --match-contract ZKCRecoveryForkTest -vv
kill "$recovery_pid"
wait "$recovery_pid" || true
trap - EXIT
```

Expect three passing cases with real historical balances. Nothing is seeded or sent to
Ethereum. The Safe owner impersonation and recovery transactions happen only on the fork.
