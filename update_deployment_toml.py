#!/usr/bin/env python3
"""
Update deployment.toml with contract addresses and deployment information.

This script allows updating specific fields in the deployment.toml configuration
for a given chain key. It preserves existing values and only updates provided fields.
"""

import argparse
import sys
import tomlkit
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description='Update deployment.toml with contract addresses'
    )
    
    # Chain configuration
    parser.add_argument(
        '--chain-key', 
        default='anvil', 
        help='Chain key in deployment.toml (default: anvil)'
    )
    
    # Contract addresses
    parser.add_argument('--admin', help='Admin address')
    parser.add_argument('--zkc-admin', help='ZKC admin address')
    parser.add_argument('--zkc-admin-2', help='ZKC secondary admin address')
    parser.add_argument('--vezkc-admin', help='veZKC admin address')
    parser.add_argument('--vezkc-admin-2', help='veZKC secondary admin address')
    parser.add_argument('--staking-rewards-admin', help='StakingRewards admin address')
    parser.add_argument('--staking-rewards-admin-2', help='StakingRewards secondary admin address')
    parser.add_argument('--supply-calculator-admin-2', help='SupplyCalculator secondary admin address')

    parser.add_argument('--zkc', help='ZKC proxy address')
    parser.add_argument('--zkc-impl', help='ZKC implementation address')
    parser.add_argument('--zkc-impl-prev', help='Previous ZKC implementation address')
    parser.add_argument('--zkc-deployer', help='ZKC deployer address')
    parser.add_argument('--vezkc', help='veZKC proxy address')
    parser.add_argument('--vezkc-impl', help='veZKC implementation address')
    parser.add_argument('--vezkc-impl-prev', help='Previous veZKC implementation address')
    parser.add_argument('--vezkc-deployer', help='veZKC deployer address')
    parser.add_argument('--staking-rewards', help='StakingRewards proxy address')
    parser.add_argument('--staking-rewards-impl', help='StakingRewards implementation address')
    parser.add_argument('--staking-rewards-impl-prev', help='Previous StakingRewards implementation address')
    parser.add_argument('--staking-rewards-deployer', help='StakingRewards deployer address')
    parser.add_argument('--povw-minter', help='POVW minter address')
    parser.add_argument('--staking-minter', help='Staking minter address')
    parser.add_argument('--supply-calculator', help='SupplyCalculator proxy address')
    parser.add_argument('--supply-calculator-impl', help='SupplyCalculator implementation address')
    parser.add_argument('--supply-calculator-admin', help='SupplyCalculator admin address')

    # Deployment metadata
    parser.add_argument('--zkc-commit', help='Git commit hash for ZKC deployment')
    parser.add_argument('--vezkc-commit', help='Git commit hash for veZKC deployment')
    parser.add_argument('--staking-rewards-commit', help='Git commit hash for StakingRewards deployment')
    parser.add_argument('--supply-calculator-commit', help='Git commit hash for SupplyCalculator deployment')
    parser.add_argument('--rpc-url', help='RPC URL for the network')
    parser.add_argument('--etherscan-api-key', help='Etherscan API key')
    
    args = parser.parse_args()
    
    # Validate chain key
    chain_key = args.chain_key
    if not chain_key:
        print("❌ Chain key cannot be empty", file=sys.stderr)
        sys.exit(1)
    
    # Find deployment.toml file
    toml_path = Path('deployment.toml')
    if not toml_path.exists():
        print("❌ deployment.toml not found in current directory", file=sys.stderr)
        sys.exit(1)
    
    try:
        # Load existing TOML
        with open(toml_path, 'r') as f:
            doc = tomlkit.load(f)
        
        # Ensure deployment section exists
        if 'deployment' not in doc:
            doc['deployment'] = tomlkit.table()
        
        # Ensure chain key section exists
        if chain_key not in doc['deployment']:
            print(f"❌ Chain key '{chain_key}' not found in deployment.toml", file=sys.stderr)
            print(f"Available chains: {list(doc['deployment'].keys())}", file=sys.stderr)
            sys.exit(1)
        
        # Track updates made
        updates = {}
        

        # Update provided values
        field_mappings = {
            'admin': args.admin,
            'zkc_admin': args.zkc_admin,
            'zkc_admin_2': args.zkc_admin_2,
            'vezkc_admin': args.vezkc_admin,
            'vezkc_admin_2': args.vezkc_admin_2,
            'staking_rewards_admin': args.staking_rewards_admin,
            'staking_rewards_admin_2': args.staking_rewards_admin_2,
            'supply_calculator_admin_2': args.supply_calculator_admin_2,
            'zkc': args.zkc,
            'zkc_impl': args.zkc_impl,
            'zkc_impl_prev': args.zkc_impl_prev,
            'zkc_deployer': args.zkc_deployer,
            'vezkc': args.vezkc,
            'vezkc_impl': args.vezkc_impl,
            'vezkc_impl_prev': args.vezkc_impl_prev,
            'vezkc_deployer': args.vezkc_deployer,
            'staking_rewards': args.staking_rewards,
            'staking_rewards_impl': args.staking_rewards_impl,
            'staking_rewards_impl_prev': args.staking_rewards_impl_prev,
            'staking_rewards_deployer': args.staking_rewards_deployer,
            'povw_minter': args.povw_minter,
            'staking_minter': args.staking_minter,
            'supply_calculator': args.supply_calculator,
            'supply_calculator_impl': args.supply_calculator_impl,
            'supply_calculator_admin': args.supply_calculator_admin,
            'zkc_commit': args.zkc_commit,
            'vezkc_commit': args.vezkc_commit,
            'staking_rewards_commit': args.staking_rewards_commit,
            'supply_calculator_commit': args.supply_calculator_commit,
            'rpc_url': args.rpc_url,
            'etherscan_api_key': args.etherscan_api_key,
        }
        
        for field, value in field_mappings.items():
            if value is not None:
                # Convert field name to TOML format
                toml_field = field.replace('_', '-')
                
                # Strip whitespace from the value (especially important for git commits)
                if isinstance(value, str):
                    value = value.strip()
                
                # Update the value
                doc['deployment'][chain_key][toml_field] = value
                updates[toml_field] = value
        
        # Write back to file
        with open(toml_path, 'w') as f:
            tomlkit.dump(doc, f)
        
        # Print updates
        if updates:
            print(f"✅ Updated deployment.toml for chain '{chain_key}':")
            for key, value in updates.items():
                # Truncate long values (like addresses) for display
                display_value = value
                if isinstance(value, str) and len(value) > 50:
                    display_value = f"{value[:10]}...{value[-10:]}"
                print(f"   {key} = {display_value}")
        else:
            print("ℹ️  No updates provided, deployment.toml unchanged")
        
    except tomlkit.exceptions.TOMLKitError as e:
        print(f"❌ Error parsing deployment.toml: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyError as e:
        print(f"❌ Missing key in deployment.toml: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()