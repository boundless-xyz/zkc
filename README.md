<p align="center">
  <img src="Boundless.png" alt="Boundless" width="400">
</p>

# ZKC

The core contracts for ZKC. Includes the token itself, as well as its associated staking and emissions contracts.

## Repository Structure

- **ZKC Token** (`src/ZKC.sol`) - ZKC ERC20
- **veZKC NFT** (`src/veZKC.sol`) - ERC721 positions issued when staking ZKC that grant governance and reward power
- **StakingVault** (`src/StakingVault.sol`) - Central orchestration contract for staking operations

## Staking System

### Overview

Users lock ZKC tokens for flexible periods (4-208 weeks) and receive a veZKC NFT positions that provides:
- **Voting Power** for governance votes (OpenZeppelin IVotes compatible)
- **Reward Power** for reward distribution (intended for PoVW emissions)
- **Time-based Decay** following "ve" style mechanics

Each address can only be issued a single position at a time, and positions are not transferrable.

### Features

#### Week-Based Locking
- **Minimum**: 4 weeks
- **Maximum**: 52 weeks (1 years)

#### Time-Based Voting/Reward Power
```
voting_power = (locked_amount × remaining_time) / MAXTIME
```
- **MAXTIME**: 52 weeks (maximum lock period)
- **Linear Decay**: Power decreases proportionally with remaining time

#### Position Management
- **Stake**: Lock ZKC tokens for chosen duration → receive veZKC NFT
- **Add Stake**: Increase ZKC amount in existing position (preserves decay rate)
- **Extend Lock**: Incremental extensions to lock periods (increases voting power)
  - Extend by additional weeks: `extendLockByWeeks(tokenId, 1)`
  - Extend to specific end time: `extendLockToTime(tokenId, targetTime)`
- **Unstake**: Direct withdrawal after lock expiry (no delay)

## Supported Interfaces

### IVotes (OpenZeppelin Governance Compatibility)
- `getVotes(account)` - Current voting power
- `getPastVotes(account, timepoint)` - Historical voting power
- `getTotalVotes()` - Total system voting power
- `getPastTotalSupply(timepoint)` - Historical total voting power
- `delegate(delegatee)` - Delegate voting power
- `delegates(account)` - Check delegation target

### IRewardPower (Custom Reward Distribution)
- `getRewardPower(account)` - Current reward power
- `getPastRewardPower(account, timepoint)` - Historical reward power
- `getTotalRewardPower()` - Total system reward power
- `getPastTotalRewardPower(timepoint)` - Historical total reward power

## 💡 Usage Examples

### Basic Staking
```solidity
// Approve ZKC tokens
zkc.approve(address(stakingVault), 1000 ether);

// Stake for 52 weeks (1 year)
uint256 tokenId = stakingVault.stake(1000 ether, 52);

// Check voting power (will be: 1000 * 52/208 = ~250)
uint256 power = veZkcToken.votingPower(tokenId);
```

### Incremental Extensions
```solidity
// You have 4 weeks remaining on your lock
// Extend by just 1 week (now 5 weeks total)
stakingVault.extendLockByWeeks(tokenId, 1);

// Or extend to specific end time (2 years from now)
stakingVault.extendLockToTime(tokenId, block.timestamp + 104 weeks);
```

### Position Management
```solidity
// Add more ZKC to existing position
stakingVault.addToStake(tokenId, 500 ether);

// Unstake after lock expires
stakingVault.unstake(tokenId); // Returns original ZKC
```

### Governance Integration
```solidity
// Delegate voting power
veZkcToken.delegate(governorAddress);

// Check voting power for governance
uint256 votes = veZkcToken.getVotes(user);
uint256 historicalVotes = veZkcToken.getPastVotes(user, blockNumber);
```

## Technical Details

**Benefits:**
- Longer locks naturally provide more power for longer periods
- Linear decay creates predictable economics
- No artificial multipliers or complex tiers
- Proven model used by major DeFi protocols

### Power Decay Example
```
Initial: 1000 ZKC locked for 208 weeks = 1000 voting power
After 52 weeks: 1000 ZKC with 156 weeks remaining = 750 voting power  
After 104 weeks: 1000 ZKC with 104 weeks remaining = 500 voting power
After 208 weeks: 1000 ZKC with 0 weeks remaining = 0 voting power
```

### Extension Mechanics
```
Current state: 4 weeks remaining
Extend by 1 week → 5 weeks remaining (not 1 week from scratch)
Extend to specific time → Set exact end date (rounded to week boundary)
```

## Governance

The system is designed for seamless integration with governance systems:

- **IVotes Compatible**: Works with OpenZeppelin Governor contracts
- **Delegation Support**: Users can delegate voting power while retaining ownership
- **Historical Queries**: Support for governance proposals with historical voting power
- **Checkpointing**: Efficient on-chain voting power tracking

## Deployment Information

### ZKC Token Deployment

**Address**: `0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555`  
**Network**: Ethereum Mainnet  
**Deployed by**: `0x139Ce48CD89155a443786FFBE32185Bb50Ae2b6`

#### Deployment Configuration
```bash
export ADMIN="0x3886eEaf95AA2bDDdf0C924925e290291f70447F"
export INITIAL_MINTER_1="0x139Ce48CD89155a443786FFBE32185Bb50Ae2b69"
export INITIAL_MINTER_2="0x48a0d6757F7AFcf7E24cc8329B18A4d99c1Aa11C"
export TOTAL_INITIAL_SUPPLY="1000000000000000000000000000"
export INITIAL_MINTER_1_AMOUNT="550000000000000000000000000"
export INITIAL_MINTER_2_AMOUNT="450000000000000000000000000"
export SALT="0x139ce48cd89155a443786ffbe32185bb50ae2b69f4aee41b0b7eab02dfb6ff33"
```