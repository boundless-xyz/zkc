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

## Delegation

### Overview

Voting and reward power can be delegated independently, allowing users to maintain control over different aspects of their staked positions:

- **Voting Delegation**: Transfer governance voting power to another address
- **Reward Delegation**: Transfer reward earning power to another address 

### Key Contract Functions

#### Voting Delegation
- `delegate(address delegatee)`: Delegate all voting power to another address
- `getVotes(address account)`: Get current voting power (own + delegated)
- `getPastVotes(address account, uint256 timepoint)`: Get historical voting power at specific block
- `delegates(address account)`: View current voting delegate

#### Reward Delegation
- `delegateRewards(address delegatee)`: Delegate all reward power to another address
- `getRewardPower(address account)`: Get current reward power (own + delegated)
- `getPastRewardPower(address account, uint256 timepoint)`: Get historical reward power
- `getRewardDelegates(address account)`: View current reward delegate

### Delegation Examples

#### Basic Separate Delegation
```solidity
// Alice stakes 1000 ZKC
veZkcToken.stake(1000 ether);

// Alice delegates voting to Bob (governance participation)
veZkcToken.delegate(bob);

// Alice delegates rewards to Charlie (rewards claiming power)
veZkcToken.delegateRewards(charlie);

// Result:
// - Alice: Owns the NFT position
// - Bob: Has Alice's voting power for governance
// - Charlie: Earns can claim rewards from Alice's stake
```

#### Withdrawal with Active Delegations Received

Delegations remain active even when delegator initiates withdrawal.

```solidity
// Alice has 1000 ZKC staked
// Bob has 500 ZKC staked and delegated voting to Alice
// Charlie has 300 ZKC staked and delegated rewards to Alice

// Alice initiates withdrawal of her own stake
veZkcToken.initiateUnstake();

// During 30-day withdrawal period:
// - Alice's own voting power: 0 (withdrawing)
// - Alice's total voting power: 500 (from Bob's delegation)
// - Alice's own reward power: 0 (withdrawing)
// - Alice's total reward power: 300 (from Charlie's delegation)

// Alice can still:
// - Vote in governance with Bob's 500 voting power
// - Claim rewards based on Charlie's 300 reward power
```

#### Revoking Delegation
```solidity
// Alice previously delegated to Bob
veZkcToken.delegate(bob);

// Alice revokes by delegating to herself
veZkcToken.delegate(alice);

// Or delegates to someone new
veZkcToken.delegate(charlie);

// Reward delegation works the same way
veZkcToken.delegateRewards(alice); // Self-delegate to revoke
```

#### Non-Transitive Delegation Example

```solidity
// Setup: Three users with staked positions
// Alice: 1000 ZKC staked
// Bob: 500 ZKC staked  
// Charlie: 200 ZKC staked

// Alice delegates her voting power to Bob
veZkcToken.delegate(bob);
// Bob now has: 500 (own) + 1000 (from Alice) = 1500 voting power

// Bob delegates his voting power to Charlie
veZkcToken.delegate(charlie);
// Charlie now has: 200 (own) + 500 (from Bob) = 700 voting power
// Note: Charlie does NOT receive Alice's 1000 - that stays with Bob

// Final distribution:
// - Alice: 0 voting power (delegated to Bob)
// - Bob: 1000 voting power (Alice's delegation only)
// - Charlie: 700 voting power (own 200 + Bob's 500)
```


## Events

### Staking Events

#### StakeCreated
Emitted when a new staking position is created.
```solidity
event StakeCreated(uint256 indexed tokenId, address indexed owner, uint256 amount)
```

#### StakeAdded
Emitted when tokens are added to an existing staking position.
```solidity
event StakeAdded(uint256 indexed tokenId, address indexed owner, uint256 addedAmount, uint256 newTotal)
```

#### UnstakeInitiated
Emitted when a user initiates the withdrawal process.
```solidity
event UnstakeInitiated(uint256 indexed tokenId, address indexed owner, uint256 withdrawableAt)
```

#### UnstakeCompleted
Emitted when a user completes withdrawal and receives their ZKC tokens.
```solidity
event UnstakeCompleted(uint256 indexed tokenId, address indexed owner, uint256 amount)
```

#### StakeBurned
Emitted when a staking position NFT is burned (after withdrawal completion).
```solidity
event StakeBurned(uint256 indexed tokenId)
```

### Delegation Events

#### DelegateChanged (Voting)
Emitted when voting delegation changes.
```solidity
event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)
```

#### DelegateVotesChanged (Voting)
Emitted when an account's voting power changes due to delegation.
```solidity
event DelegateVotesChanged(address indexed delegate, uint256 previousVotes, uint256 newVotes)
```

#### RewardDelegateChanged (Rewards)
Emitted when reward delegation changes.
```solidity
event RewardDelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)
```

#### DelegateRewardsChanged (Rewards)
Emitted when an account's reward power changes due to delegation.
```solidity
event DelegateRewardsChanged(address indexed delegate, uint256 previousRewards, uint256 newRewards)
```

### ZKC Token Events

#### PoVWRewardsClaimed
Emitted when Proof of Verifiable Work rewards are minted for a recipient.
```solidity
event PoVWRewardsClaimed(address indexed recipient, uint256 amount)
```

#### StakingRewardsClaimed
Emitted when staking rewards are minted for a recipient.
```solidity
event StakingRewardsClaimed(address indexed recipient, uint256 amount)
```

### Standard ERC721 Events

#### Transfer
Emitted when a veZKC NFT is minted, burned, or would transfer (though transfers are disabled).
```solidity
event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)
```

#### Approval
Emitted when approval is granted (though transfers are disabled, this is still part of ERC721).
```solidity
event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId)
```

#### ApprovalForAll
Emitted when operator approval is set (though transfers are disabled).
```solidity
event ApprovalForAll(address indexed owner, address indexed operator, bool approved)
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
