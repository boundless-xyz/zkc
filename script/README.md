# ZKC Deployment Guide

Simple guide for deploying and upgrading ZKC contracts using the `manage` script.

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

## Commands

| Command | Description |
|---------|-------------|
| `deploy-zkc` | Deploy ZKC token |
| `deploy-vezkc` | Deploy veZKC staking (requires ZKC) |
| `upgrade-zkc` | Upgrade ZKC implementation |
| `upgrade-vezkc` | Upgrade veZKC implementation |
| `upgrade-staking` | Upgrade StakingRewards implementation |
| `upgrade-all` | Upgrade all implementations |

## Options

- `--broadcast`: Send transactions to network
- `--verify`: Verify on Etherscan  
- `--fireblocks` / `-f`: Use Fireblocks signing

## Networks

- `anvil`: Local development
- `ethereum-mainnet`: Ethereum Mainnet
- `ethereum-sepolia`: Ethereum Sepolia testnet

## Files

- `deployment.toml`: Contract addresses (auto-updated)
- `deployment_secrets.toml`: Private keys, RPC URLs (gitignored)

## Examples

```bash
# Local development
CHAIN_KEY=anvil ./script/manage deploy-zkc --broadcast

# Testnet
CHAIN_KEY=ethereum-sepolia ./script/manage deploy-zkc --broadcast --verify

# Mainnet production
CHAIN_KEY=ethereum-mainnet ./script/manage deploy-zkc --fireblocks --broadcast --verify
```