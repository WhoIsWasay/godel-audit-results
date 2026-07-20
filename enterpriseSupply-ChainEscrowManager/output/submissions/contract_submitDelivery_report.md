### [VULNERABILITY CLASS]
MEDIUM: Off-by-one bound check allows a supplier to submit... in `submitDelivery`

**Vulnerability Detail:**
Off-by-one bound check allows a supplier to submit a delivery for an uninitialized milestone (milestoneId equal to milestoneCount), creating a phantom delivery with default zero-weight/zero-amount. This violates the milestone initialization boundary invariant.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(milestoneId < e.milestoneCount);` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
require(milestoneId <= e.milestoneCount, "Invalid milestone ID");
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: Off-by-one allows phantom milestone submission
milestoneCount = 0
milestoneId = 0
milestoneWeight = 0
milestoneAmount = 0
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/contract_submitDelivery_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function submitDelivery(uint256 escrowId, uint256 milestoneId) external onlySupplier(escrowId) validEscrow(escrowId) {
    Escrow storage e = escrows[escrowId];
    require(e.status == EscrowStatus.ACTIVE, "Escrow not active");
    require(milestoneId < e.milestoneCount, "Invalid milestone ID");

    Milestone storage m = e.milestones[milestoneId];
    require(m.status == MilestoneStatus.PENDING, "Milestone not pending");

    m.status = MilestoneStatus.DELIVERED;
    m.deliveredAt = uint64(block.timestamp);

    SupplierMetrics storage metrics = supplierProfiles[e.supplier];
    metrics.totalDeliveries++;

    emit DeliverySubmitted(escrowId, milestoneId);
}
```
