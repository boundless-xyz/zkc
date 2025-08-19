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
- **Maximum**: 208 weeks (4 years)
- **Rounding**: All lock end times are rounded down to the nearest week boundary for consistency

#### Staking Management
- **Stake**: Lock ZKC tokens for chosen duration → receive veZKC NFT
- **Add Stake (Top-up)**: Increase ZKC amount in existing position (preserves decay rate)
  - **Note**: Cannot top-up expired locks - must extend first
- **Extend Lock**: Incremental extensions to lock periods (increases voting power)
  - Extend by additional weeks: `extendLockByWeeks(tokenId, 1)`
  - Extend to specific end time: `extendLockToTime(tokenId, targetTime)`
  - **Expired Lock Extensions**: Can extend expired locks (refreshes commitment)
- **Unstake**: Direct withdrawal after lock expiry (no delay)
- **Check Position**: Use `getStakedAmountAndExpiry(address)` to get exact lock amount and expiry timestamp

### Claiming Emissions

The portion of ZKC emissions that a user is eligible to claim is calculated based on their "Reward Power". 

Rewards Power is accessible via the IRewards interface. The contracts that enable users to claim rewards use these values to calculate the portion of emissions that should be transferred to the user. 

Currently reward power is simply equal to the amount of ZKC a user has staked, with no decay or adjustments to the power over time. **Important**: Reward power persists even after locks expire, unlike voting power which decays to zero.

### Governance

A users weight in governance votes is calculated from their "Voting Power".

Voting power is accessible via the IVotes interface. Governance contracts use these values to compute a users voting power during a vote.

Voting power decays over time following the "voting escrow" model. Committing stake for longer provides more power for longer periods. 

```
voting_power = (staked_amount × remaining_time) / MAXTIME
```

- **MAXTIME**: 208 weeks (maximum stake period)
- **Linear Decay**: Power decreases proportionally with remaining time

#### Examples

##### Voting Decay
```
Example 1: Stake for maximum time (208 weeks)
Initial: 1000 ZKC staked for 208 weeks = 1000 voting power (1000 × 208/208)
After 52 weeks: 1000 ZKC with 156 weeks remaining = 750 voting power  
After 104 weeks: 1000 ZKC with 104 weeks remaining = 500 voting power
After 208 weeks: 1000 ZKC with 0 weeks remaining = 0 voting power

Example 2: Stake for quarter maximum time (52 weeks)
Initial: 1000 ZKC locked for 52 weeks = 250 voting power (1000 × 52/208)
After 26 weeks: 1000 ZKC with 26 weeks remaining = 125 voting power
After 52 weeks: 1000 ZKC with 0 weeks remaining = 0 voting power
```

##### Adding additional stake
Adding additional stake to an existing position boosts your voting power while preserving the remaining lock time.

```
Initial: 1000 ZKC locked for 52 weeks = 250 voting power (1000 × 52/208)
After 26 weeks: 1000 ZKC with 26 weeks remaining = 125 voting power
Add 500 ZKC: 1500 ZKC with 26 weeks remaining = 187.5 voting power (1500 × 26/208)

**Important**: Cannot add stake to expired positions. If your lock has expired (0 weeks remaining), you must extend the lock first before adding more ZKC.
```

##### Extending staking period
Extending your staking period increases your voting power by giving you more time remaining on your lock.

```
Initial: 1000 ZKC locked for 26 weeks = 125 voting power (1000 × 26/208)
Extend to 52 weeks: 1000 ZKC with 52 weeks remaining = 250 voting power (1000 × 52/208)
```


##### Expired Lock Management
When locks expire, voting power becomes zero but reward power persists. You can refresh your commitment by extending the expired lock:

```
Expired Position: 1000 ZKC with 0 weeks remaining
- Voting Power: 0 (expired)
- Reward Power: 1000 ZKC (persists)

Extend to 52 weeks: 1000 ZKC with 52 weeks remaining
- Voting Power: 250 (1000 × 52/208) - refreshed!
- Reward Power: 1000 ZKC (unchanged)

Now you can top-up: Add 500 ZKC to the refreshed position
- Voting Power: 375 (1500 × 52/208)
- Reward Power: 1500 ZKC
```

**Key Points:**
- Expired locks retain reward power but lose voting power
- Must extend expired locks before topping up
- Extending refreshes voting power based on new lock duration
- Top-ups are only allowed on active (non-expired) locks

##### Week Rounding
All lock end times are automatically rounded down to the nearest week boundary (Thursday 00:00 UTC) for consistency:

```
Example: Stake on Monday with 30-day duration
- Requested end: Monday + 30 days
- Actual end: Previous Thursday 00:00 UTC (rounded down)
- Use getStakedAmountAndExpiry() to see exact expiry timestamp
```

#### Delegation System

veZKC supports **dual delegation** - you can independently delegate your voting power and reward collection rights to different addresses.

##### Voting Delegation (Governance)

Delegate your voting power to another veZKC holder for governance participation:

```solidity
// Delegate voting power to another staker
veZkcToken.delegate(expertGovernanceUser);

// Check delegation status
address votingDelegate = veZkcToken.delegates(msg.sender);

// Undelegate (regain voting control)
veZkcToken.delegate(address(0));
```

**Key Requirements:**
- **Lock Alignment**: Both delegator and delegatee must have **identical lock end times**
- **Position Required**: Delegatee must have an active veZKC position
- **Power Transfer**: Your voting power moves to the delegatee (you get 0 voting power)
- **Decay Together**: Delegated power decays at the same rate since locks are aligned

**Lock Extension Behavior:**
- **While Delegated**: You cannot extend your own lock - it follows the delegatee's lock
- **Delegatee Extensions**: When the delegatee extends their lock, your lock is also extended
- **After Undelegation**: You regain control and can extend your lock independently
- **Inherited Duration**: Upon undelegation, you keep the delegatee's last lock end time

```solidity
// Example delegation flow
// 1. Both users align their locks to the same end time
aliceToken.extendStakeLockup(commonLockEnd);
bobToken.extendStakeLockup(commonLockEnd);

// 2. Alice delegates to Bob
aliceToken.delegate(bob);

// 3. Bob extends his lock (Alice's lock extends too automatically)
bobToken.extendStakeLockup(longerLockEnd);

// 4. Alice undelegates and inherits Bob's extended lock end
aliceToken.delegate(address(0));
// Alice's lock end is now `longerLockEnd`
```

##### Reward Delegation (Collection)

Delegate your reward collection rights to any address for flexible reward management:

```solidity
// Delegate reward collection to treasury (no position required)
veZkcToken.delegateRewards(treasuryAddress);

// Check reward delegation status
address rewardCollector = veZkcToken.rewardDelegates(msg.sender);

// Undelegate rewards (regain collection rights)
veZkcToken.delegateRewards(address(0));
```

**Key Features:**
- **No Position Required**: Delegate to any address (treasury, multisig, etc.)
- **No Time Constraints**: Works regardless of lock durations
- **Power Transfer**: Your reward power moves to the collector (you get 0 reward power)
- **No Decay**: Reward power never decays, even after lock expiry

##### Independent Delegation

Voting and reward delegation are completely independent:

```solidity
// Delegate voting to governance expert
veZkcToken.delegate(governanceExpert);

// Delegate rewards to treasury
veZkcToken.delegateRewards(treasury);

// Check status
assert(veZkcToken.delegates(msg.sender) == governanceExpert);
assert(veZkcToken.rewardDelegates(msg.sender) == treasury);

// Power distribution
assert(veZkcToken.getVotes(msg.sender) == 0);           // No voting power
assert(veZkcToken.getRewards(msg.sender) == 0);         // No reward power
assert(veZkcToken.getVotes(governanceExpert) > 0);      // Has your voting power
assert(veZkcToken.getRewards(treasury) > 0);            // Has your reward power
```

##### Common Delegation Patterns

**DAO Treasury Management:**
```solidity
// Route rewards to DAO treasury for collective management
veZkcToken.delegateRewards(daoTreasury);
// Keep voting power for personal governance participation
```

**Full DAO Participation:**
```solidity
// Delegate both voting and rewards to DAO
veZkcToken.delegate(daoGovernanceMultisig);      // Requires matching lock
veZkcToken.delegateRewards(daoTreasuryMultisig); // No lock requirement
```

**Expert Governance + Personal Rewards:**
```solidity
// Let governance expert vote, keep rewards personally
veZkcToken.delegate(governanceExpert);    // Expert handles governance
veZkcToken.delegateRewards(address(0));   // Keep rewards yourself
```

##### Important Notes

- **Delegation is Per-Account**: Each user can only delegate to one address for each type
- **Undelegation Restores Control**: You can always undelegate to regain control
- **Position Modifications**: Adding stake or extending locks works normally while delegated
- **Lock Inheritance**: Voting delegation may extend your lock beyond your original commitment
- **Signature Support**: Both delegation types support off-chain signatures via `delegateBySig()`

#### IVotes Compatibility

veZKC is IVotes compatible, supporting historical queries of voting power and voting delegation.


## Usage Examples

### Basic Staking
```solidity
// Approve ZKC tokens
zkc.approve(address(veZkcToken), 1000 ether);

// Stake for 52 weeks (1/4 maximum lock)
uint256 tokenId = veZkcToken.stake(1000 ether, block.timestamp + 52 weeks);

// Check voting power (will be: 1000 * 52/208 = 250)
// Get exact lock expiry (rounded to week boundary)
(uint256 amount, uint256 expiry) = veZkcToken.getStakedAmountAndExpiry(msg.sender);
uint256 power = veZkcToken.getVotes(msg.sender);
```

### Incremental Extensions
```solidity
// Extend to specific end time (4 years from now - maximum)
veZkcToken.extendLockToTime(tokenId, block.timestamp + 208 weeks);

// Extend expired lock (refresh commitment)
// This works even if the lock has already expired
veZkcToken.extendLockToTime(tokenId, block.timestamp + 52 weeks);
```

### Position Management
```solidity
// Check your exact position details
(uint256 amount, uint256 expiry) = veZkcToken.getStakedAmountAndExpiry(msg.sender);

// Add more ZKC to existing position (only if lock is active)
veZkcToken.addToStake(tokenId, 500 ether);

// Unstake after lock expires
veZkcToken.unstake(tokenId); // Returns original ZKC
```

### Expired Lock Management
```solidity
// Check status of expired position
uint256 votingPower = veZkcToken.getVotes(msg.sender); // 0 (expired)
uint256 rewardPower = veZkcToken.getRewardPower(msg.sender); // 1000 (persists)
(uint256 amount, uint256 expiry) = veZkcToken.getStakedAmountAndExpiry(msg.sender);
// amount = 1000, expiry = 1234567890 (past timestamp)

// Extend expired lock to refresh voting power
veZkcToken.extendLockToTime(tokenId, block.timestamp + 52 weeks);
uint256 newVotingPower = veZkcToken.getVotes(msg.sender); // 250 (refreshed)

// Now you can top-up the refreshed position
veZkcToken.addToStake(tokenId, 500 ether);
uint256 finalVotingPower = veZkcToken.getVotes(msg.sender); // 375
```

### Delegation Examples

#### Basic Voting Delegation
```solidity
// Both users need matching lock end times
uint256 commonLockEnd = block.timestamp + 104 weeks;

// Alice and Bob align their locks
alice.extendStakeLockup(commonLockEnd);
bob.extendStakeLockup(commonLockEnd);

// Alice delegates voting power to Bob
alice.delegate(bob);

// Check delegation
assert(alice.delegates(alice) == bob);
assert(alice.getVotes(alice) == 0);                // Alice has no voting power
assert(bob.getVotes(bob) == aliceVotes + bobVotes); // Bob has combined power
```

#### Reward Collection Delegation
```solidity
// Alice delegates reward collection to treasury (no lock matching needed)
alice.delegateRewards(treasury);

// Check reward delegation
assert(alice.rewardDelegates(alice) == treasury);
assert(alice.getRewards(alice) == 0);              // Alice has no reward power
assert(alice.getRewards(treasury) == aliceAmount); // Treasury collects Alice's rewards
```

#### Mixed Delegation Strategy
```solidity
// Alice wants expert governance but personal reward control
alice.delegate(governanceExpert);        // Requires lock alignment
alice.delegateRewards(address(0));       // Keep rewards (undelegate if needed)

// Bob wants DAO treasury rewards but personal voting
bob.delegateRewards(daoTreasury);        // No lock requirement
bob.delegate(address(0));                // Keep voting power (undelegate if needed)
```

#### Lock Extension Impact on Delegation
```solidity
// After Alice delegates to Bob, Bob extends his lock
bob.extendStakeLockup(block.timestamp + 156 weeks);

// Alice's lock is automatically extended too (while delegated)
(, uint256 aliceLockEnd) = alice.getStakedAmountAndExpiry(alice);
assert(aliceLockEnd == block.timestamp + 156 weeks);

// Alice undelegates and inherits the extended lock end
alice.delegate(address(0));
assert(alice.getVotes(alice) > 0);       // Alice has voting power with extended lock
(, uint256 inheritedEnd) = alice.getStakedAmountAndExpiry(alice);
assert(inheritedEnd == block.timestamp + 156 weeks); // Inherited Bob's lock end
```

### Governance Integration
```solidity
// Basic delegation for governance
veZkcToken.delegate(governorAddress);

// Check voting power for governance
uint256 votes = veZkcToken.getVotes(user);
uint256 historicalVotes = veZkcToken.getPastVotes(user, blockNumber);

// Advanced delegation management
address currentDelegate = veZkcToken.delegates(user);
address rewardCollector = veZkcToken.rewardDelegates(user);
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
