<p align="center">
  <img src="Boundless.png" alt="Boundless" width="400">
</p>

# ZKC

The core contracts for ZKC. Includes the token itself, as well as its associated staking and emissions contracts.

## Repository Structure

- **ZKC Token** (`src/ZKC.sol`) - ZKC ERC20 with epoch-based inflation and emissions
- **veZKC NFT** (`src/veZKC.sol`) - ERC721 positions issued when staking ZKC that grant governance and reward power
- **Rewards** (`rewards/`) - Contracts that allow users to claim their portion of emitted ZKC rewards each epoch.

## ZKC

### Epochs

ZKC distributes emissions every epoch:

- **Initial Supply**: 1 billion ZKC
- **Epoch Duration**: 2 days
- **Epochs Per Year**: 182 epochs

#### Emission Rate

The annual emission rate decreases over time. Emissions are divided equally across epochs throughout the year:
- **Year 0**: 7.0% annual
- **Year 1**: 6.5% annual  
- **Year 2**: 6.0% annual
- **Year 3**: 5.5% annual
- **Year 4**: 5.0% annual
- **Year 5**: 4.5% annual
- **Year 6**: 4.0% annual
- **Year 7**: 3.5% annual
- **Year 8+**: 3.0% annual (minimum rate)

#### Emissions Distribution

Each epoch's new emissions are allocated to two external contracts for distribution to users:
- **75% to PoVW Provers (Proof of Verifiable Work)**: Rewards for provers participating in the network
  - see `<TODO>`
- **25% to ZKC Stakers**: Distributed to ZKC stakers (veZKC holders)
  - see `rewards/StakingRewards.sol`

Emissions occur at the end of each epoch.

## veZKC

### Overview

Users stake ZKC tokens for a fixed period between (4-208 weeks) and receive a veZKC NFT positions that provides:
- **Ability to participate in governance** eligibility for participating in governance votes
- **Ability to claim ZKC emissions** eligibility for claiming ZKC emissions

Once staked, ZKC can not be unstaked the end of the commited period. Each address can only be issued a single position at a time. Positions are not transferrable.

#### Staking Periods
- **Minimum**: 4 weeks
- **Maximum**: 104 weeks (2 years)

#### Staking Management
- **Stake**: Lock ZKC tokens for chosen duration → receive veZKC NFT
- **Add Stake**: Increase ZKC amount in existing position (preserves decay rate)
- **Extend Lock**: Incremental extensions to lock periods (increases voting power)
  - Extend by additional weeks: `extendLockByWeeks(tokenId, 1)`
  - Extend to specific end time: `extendLockToTime(tokenId, targetTime)`
- **Unstake**: Direct withdrawal after lock expiry (no delay)

### Claiming Emissions

The portion of ZKC emissions that a user is eligible to claim is calculated based on their "Reward Power". 

Rewards Power is accessible via the IRewards interface. The contracts that enable users to claim rewards use these values to calculate the portion of emissions that should be transferred to the user. 

Currently reward power is simply equal to the amount of ZKC a user has staked, with no decay or adjustments to the power over time.

### Governance

A users weight in governance votes is calculated from their "Voting Power".

Voting power is accessible via the IVotes interface. Governance contracts use these values to compute a users voting power during a vote.

Voting power decays over time following the "voting escrow" model. Committing stake for longer provides more power for longer periods. 

```
voting_power = (staked_amount × remaining_time) / MAXTIME
```

- **MAXTIME**: 104 weeks (maximum stake period)
- **Linear Decay**: Power decreases proportionally with remaining time

#### Examples

##### Voting Decay
```
Example 1: Stake for maximum time (104 weeks)
Initial: 1000 ZKC staked for 104 weeks = 1000 voting power (1000 × 104/104)
After 26 weeks: 1000 ZKC with 78 weeks remaining = 750 voting power  
After 52 weeks: 1000 ZKC with 52 weeks remaining = 500 voting power
After 104 weeks: 1000 ZKC with 0 weeks remaining = 0 voting power

Example 2: Stake for half maximum time (52 weeks)
Initial: 1000 ZKC locked for 52 weeks = 500 voting power (1000 × 52/104)
After 26 weeks: 1000 ZKC with 26 weeks remaining = 250 voting power
After 52 weeks: 1000 ZKC with 0 weeks remaining = 0 voting power
```

##### Adding additional stake
Adding additional stake to an existing position boosts your voting power while preserving the remaining lock time.

```
Initial: 1000 ZKC locked for 52 weeks = 500 voting power (1000 × 52/104)
After 26 weeks: 1000 ZKC with 26 weeks remaining = 250 voting power
Add 500 ZKC: 1500 ZKC with 26 weeks remaining = 375 voting power (1500 × 26/104)
```

##### Extending staking period
Extending your staking period increases your voting power by giving you more time remaining on your lock.

```
Initial: 1000 ZKC locked for 26 weeks = 250 voting power (1000 × 26/104)
Extend to 52 weeks: 1000 ZKC with 52 weeks remaining = 500 voting power (1000 × 52/104)
```


#### IVotes Compatibility

veZKC is IVotes compatible, supporting historical queries of voting power and voting delegation.


## Usage Examples

### Basic Staking
```solidity
// Approve ZKC tokens
zkc.approve(address(veZkcToken), 1000 ether);

// Stake for 52 weeks (1/2 maximum lock)
uint256 tokenId = veZkcToken.stake(1000 ether, block.timestamp + 52 weeks);

// Check voting power (will be: 1000 * 52/104 = 500)
uint256 power = veZkcToken.getVotes(msg.sender);
```

### Incremental Extensions
```solidity
// Extend to specific end time (2 years from now)
veZkcToken.extendLockToTime(tokenId, block.timestamp + 104 weeks);
```

### Position Management
```solidity
// Add more ZKC to existing position
veZkcToken.addToStake(tokenId, 500 ether);

// Unstake after lock expires
veZkcToken.unstake(tokenId); // Returns original ZKC
```

### Governance Integration
```solidity
// Delegate voting power
veZkcToken.delegate(governorAddress);

// Check voting power for governance
uint256 votes = veZkcToken.getVotes(user);
uint256 historicalVotes = veZkcToken.getPastVotes(user, blockNumber);
```




## Deployments

### ZKC

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
