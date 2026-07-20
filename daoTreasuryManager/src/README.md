# DAO Treasury Manager - Formal Verification Benchmark

## Protocol Purpose
The `DAOTreasuryManager` handles epoch-based budgeting, grant proposal submissions, and dynamically risk-adjusted treasury allocations. It restricts overspending per epoch while allowing granular tracking of votes and budget reclamation for cancelled proposals.

## Core Invariants
The formal verification tool must prove or disprove the following mathematical invariants using symbolic execution of the smart contract's functions in isolation:

1. **Vote Accumulation Fidelity**
   In `castVote`, the proposal's vote tally must precisely reflect the addition of the input `rawTokenBalance` without loss of voting power.
   - *Property:* If `support` is true, `votesFor` post-state MUST exactly equal `votesFor` pre-state + `rawTokenBalance`.

2. **Budget Reclamation Monotonicity**
   In `reclaimCancelledBudget`, freeing up funds must never increase the total amount recorded as spent for that epoch.
   - *Property:* `epochSpent[epochId]` post-state MUST be less than or equal to `epochSpent[epochId]` pre-state.

3. **Risk Adjustment Ceiling**
   In `calculateRiskAdjustedGrant`, the combined application of two sub-100% risk multipliers must never result in a grant larger than the original requested base amount.
   - *Property:* `adjustedGrant <= baseAmount` for all valid inputs.

4. **Time-Weight Overflow Safety**
   In `calculateVotingPower`, the application of time multipliers and base factors must not trigger an arithmetic overflow, ensuring governance calculations do not revert.
   - *Property:* Function must not overflow `type(uint256).max` given the `require` preconditions inside the `unchecked` block.

5. **Batch Allocation Identity**
   In `batchAllocateStandardGrants`, the amount processed and added to `epochSpent` must equal the exact requested `totalBatchAmount` without truncation.
   - *Property:* `validatedAmount == totalBatchAmount` for any input passing the initial `require` constraints.

## Expected Function Behaviors
- `initializeEpoch`: Increments the epoch and sets its maximum budget limit.
- `createProposal`: Registers a proposal and eagerly adds its cost to `epochSpent`.
- `castVote`: Adds a user's token balance to the respective `votesFor` or `votesAgainst` tally.
- `cancelProposal`: Flags a pending proposal as cancelled.
- `reclaimCancelledBudget`: Reconciles the `epochSpent` tracking for a cancelled proposal.
- `calculateRiskAdjustedGrant`: Pure math calculating dual-percentage base adjustment.
- `calculateVotingPower`: Pure math applying duration multipliers to base balances.
- `batchAllocateStandardGrants`: Divides and verifies standardized budget chunks.

## Out of Scope Assumptions
- **Reentrancy & Cross-Contract:** Not applicable. Treat state transitions as atomic.
- **Access Control:** Malicious `msg.sender` manipulation or compromised admin keys are out of scope.
- **Oracle / Timestamp:** MEV and block timestamp manipulations are out of scope. 
- **Gas / DoS:** Gas griefing is strictly out of scope.

## Scope Note for Verification Tooling
This benchmark is scoped strictly to **pure arithmetic, struct manipulation, casting safety, and single-function state logic**. The tooling should be able to evaluate the constraints strictly by mapping the Solidity AST to an SMT solver (e.g., Z3) and evaluating symbolic inputs against the Core Invariants in a single-function isolation context.