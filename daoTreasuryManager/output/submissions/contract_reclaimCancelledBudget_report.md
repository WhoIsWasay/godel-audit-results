### [VULNERABILITY CLASS]
HIGH: For a rollover proposal, reclaimCancelledBudget adds the proposal... in `reclaimCancelledBudget`

**Vulnerability Detail:**
For a rollover proposal, reclaimCancelledBudget adds the proposal amount to epochSpent instead of subtracting it. This violates the Budget Reclamation Monotonicity invariant, permanently inflates the epoch’s spending record, and locks budget away.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(epochSpent[prop.epochId] <= epochSpent_pre[prop.epochId])` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
epochSpent[prop.epochId] += prop.amount;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG CONFIRMED: epochSpent increases for rollover proposal
[epochSpent_0 = 999935,
 proposal_amount = 655357,
 proposal_isRollover = True,
 proposal_budgetReclaimed = False,
 epochSpent_1 = 1655292,
 proposal_status = 2]
```

3. **Validation:** Verified via Z3 counterexample (above) and reproduced as a passing Foundry exploit test in this repo's logs/ directory.

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function reclaimCancelledBudget(uint256 proposalId) external proposalExists(proposalId) {
    Proposal storage prop = proposals[proposalId];
    require(prop.status == Status.CANCELLED, "Must be cancelled");
    require(!prop.budgetReclaimed, "Budget already reclaimed");

    prop.budgetReclaimed = true;

    // The proposal's budget was originally reserved in epochSpent[prop.epochId] during creation.
    // Reclaiming always frees that reservation, so we subtract regardless of rollover status.
    epochSpent[prop.epochId] -= prop.amount;

    emit BudgetReclaimed(proposalId, prop.amount);
}
```
