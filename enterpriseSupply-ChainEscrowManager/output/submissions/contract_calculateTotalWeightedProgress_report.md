### [VULNERABILITY CLASS]
HIGH: The weighted average calculation divides the sum of... in `calculateTotalWeightedProgress`

**Vulnerability Detail:**
The weighted average calculation divides the sum of (qualityScore * weight) by the number of approved milestones, instead of the sum of weights. Since weights are in basis points (up to 10000), the result can exceed the valid quality score maximum of 100 by a factor of up to 10000, violating the invariant that the returned progress never exceeds 100.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(totalWeightedScore / activeMilestonesCount <= 100)` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
return totalWeightedScore / activeMilestonesCount;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND:
[result = 1000000,
 weight = 10000,
 qualityScore = 100,
 totalWeightedScore_0 = 1000000,
 activeMilestonesCount_0 = 1]
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/contract_calculateTotalWeightedProgress_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function calculateTotalWeightedProgress(uint256 escrowId) external view validEscrow(escrowId) returns (uint256) {
    Escrow storage e = escrows[escrowId];
    
    uint256 totalWeightedScore = 0;
    uint256 totalWeight = 0;

    for (uint256 i = 0; i < e.milestoneCount; i++) {
        if (e.milestones[i].status == MilestoneStatus.APPROVED) {
            totalWeightedScore += e.milestones[i].qualityScore * e.milestones[i].weight;
            totalWeight += e.milestones[i].weight;
        }
    }

    if (totalWeight == 0) return 0;

    // The weighted average is now correctly computed by dividing by the sum of the weights,
    // guaranteeing the result stays within the [0, 100] interval.
    return totalWeightedScore / totalWeight;
}
```
