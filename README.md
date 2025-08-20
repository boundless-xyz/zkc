<p align="center">
  <img src="Boundless.png" alt="Boundless" width="400">
</p>

# ZKC

The core contracts for ZKC. Includes the token itself, as well as its associated staking and emissions contracts.

## Repository Structure

* **ZKC Token (`src/ZKC.sol`)** is the main ERC20 token with epoch-based inflation and emissions.

* **veZKC NFT (`src/veZKC.sol`)** represents ERC721 positions issued when staking ZKC that grant governance and reward power.

* **Rewards (`rewards/`)** contains contracts that allow users to claim their portion of emitted ZKC rewards each epoch.

## ZKC

### Epochs

ZKC distributes emissions every epoch. The initial supply is 1 billion ZKC. Each epoch lasts 2 days, resulting in 182 epochs per year.

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

Each epoch's new emissions are allocated to two external contracts for distribution.

**75% goes to Provers generating ZK proofs**. Submitting _Proofs of Verifiable Work_ (PoVW) entitles provers to a portion of emitted ZKC.

**25% goes to ZKC stakers**. Staking ZKC for veZKC entitles holders to a portion of emitted ZKC.

Emissions occur at the end of each epoch.

## veZKC

### Overview

Users stake ZKC tokens and receive a veZKC NFT position that provides eligibility for participating in governance votes and claiming ZKC emissions.

Users stake ZKC without committing to a specific duration and receive full voting and reward power immediately upon staking. 

To unstake, users must initiate withdrawal and wait 30 days before completing the process to receive their ZKC. Voting and reward powers immediately drop to 0 when withdrawal is initiated.

Each address can only have one active position at a time. Positions are non-transferrable.

### Contract Architecture

The contract consists of three main components:

**Staking Component** (`src/components/Staking.sol`) handles core staking operations including minting veZKC, managing stake amounts, and processing withdrawals.

**Votes Component** (`src/components/Votes.sol`) implements the IVotes interface for governance compatibility, providing voting power queries and delegation functionality.

**Rewards Component** (`src/components/Rewards.sol`) implements the IRewards interface for reward distribution systems, providing reward power calculations for PoVW rewards and Staking rewards.

## Staking

### Operations

Staking locks ZKC tokens and mints a veZKC NFT. Adding stake increases the ZKC amount in an existing position.

Initiating withdrawal starts the 30-day withdrawal period and causes powers to drop to 0 immediately. Completing withdrawal allows claiming ZKC after 30 days and burns the NFT. You cannot add stake to a position that has initiated withdrawal.

Users can check their position using `getStakedAmountAndWithdrawalTime(address)` to get position details.

## Power Calculations

Both voting and reward powers are calculated via the `IVotes` and `IRewards` interfaces.

### Rewards

The portion of ZKC emissions that a user is eligible to claim is calculated based on their reward power.

Reward power is accessible via the IRewards interface. The contracts that enable users to claim rewards use these values to calculate the portion of emissions that should be transferred to the user.

Reward power drops to zero immediately when withdrawal is initiated, ensuring only committed stakers receive rewards.

### Votes

A user's weight in governance votes is calculated from their voting power.

Voting power is accessible via the IVotes interface. Governance contracts use these values to compute a user's voting power during a vote.

Voting power drops to zero immediately when withdrawal is initiated, ensuring only committed stakers can participate in governance votes.

#### Examples

##### Basic Staking
```
Stake 1000 ZKC:
- Voting Power: 1000
- Reward Power: 1000
- Status: Active

After 6 months:
- Voting Power: 1000 (no decay)
- Reward Power: 1000 (no decay)
- Status: Still active
```

##### Withdrawal Process
```
Initial State: 1000 ZKC staked
- Voting Power: 1000
- Reward Power: 1000

Initiate Withdrawal:
- Voting Power: 0 (immediate drop)
- Reward Power: 0 (immediate drop)
- Withdrawal Period: 30 days remaining

After 30 days:
- Can complete withdrawal and receive 1000 ZKC
- NFT is burned, no more position
```

##### Adding Additional Stake
```
Initial: 1000 ZKC staked
- Voting Power: 1000
- Reward Power: 1000

Add 500 ZKC:
- Voting Power: 1500
- Reward Power: 1500
- Position grows in size

Note: Cannot add stake once withdrawal is initiated
```

veZKC is IVotes compatible, supporting historical queries of voting power and voting delegation.


## Usage Examples

### Basic Staking
```solidity
// Approve ZKC tokens
zkc.approve(address(veZkcToken), 1000 ether);

// Stake (no lock period required)
uint256 tokenId = veZkcToken.stake(1000 ether);

// Check powers (both will be 1000 with scalar = 1)
uint256 votingPower = veZkcToken.getVotes(msg.sender);
uint256 rewardPower = veZkcToken.getRewards(msg.sender);
```

### Position Management
```solidity
// Check your position details
(uint256 amount, uint256 withdrawableAt) = veZkcToken.getStakedAmountAndWithdrawalTime(msg.sender);
// withdrawableAt = 0 if not withdrawing, timestamp if withdrawal initiated

// Add more ZKC to existing position (only if not withdrawing)
veZkcToken.addToStake(500 ether);

// Add to any position by token ID (donation)
veZkcToken.addToStakeByTokenId(tokenId, 100 ether);
```

### Withdrawal Process
```solidity
// Start withdrawal process (powers drop to 0 immediately)
veZkcToken.initiateUnstake();

// Check withdrawal status
(uint256 amount, uint256 withdrawableAt) = veZkcToken.getStakedAmountAndWithdrawalTime(msg.sender);
bool canWithdraw = block.timestamp >= withdrawableAt;

// Complete withdrawal after 30 days
if (canWithdraw) {
    veZkcToken.completeUnstake(); // Returns ZKC, burns NFT
}
```

### Governance Integration
```solidity
// Delegate voting power (standard IVotes)
veZkcToken.delegate(governorAddress);

// Check voting power for governance
uint256 votes = veZkcToken.getVotes(user);
uint256 historicalVotes = veZkcToken.getPastVotes(user, timestamp);

// Check total voting supply
uint256 totalVotes = veZkcToken.getPastTotalSupply(timestamp);
```

### Permit Support
```solidity
// Stake with permit (gasless approval)
veZkcToken.stakeWithPermit(
    1000 ether,
    deadline,
    v, r, s
);

// Add to stake with permit
veZkcToken.addToStakeWithPermit(
    500 ether,
    deadline,
    v, r, s
);
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
