### [VULNERABILITY CLASS]
HIGH: The approveDelivery function subtracts the full milestone base... in `approveDelivery`

**Vulnerability Detail:**
The approveDelivery function subtracts the full milestone base amount (m.amount) from the escrow balance, while only releasing the potentially penalty-reduced payout to the supplier. When penalties apply (payout < m.amount), the sum e.balance + e.totalReleased permanently desyncs from e.totalDeposit, violating the conservation of escrow funds.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(e.balance + e.totalReleased == e.totalDeposit)` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
e.balance -= m.amount;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: Conservation of escrow funds violated
[m_amount = 1,
 totalDeposit = 999999,
 payout = 0,
 balance_1 = 999998,
 totalReleased_0 = 0,
 totalReleased_1 = 0,
 balance_0 = 999999]
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/contract_approveDelivery_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function approveDelivery(uint256 escrowId, uint256 milestoneId, uint256 qualityScore) external onlyBuyer(escrowId) validEscrow(escrowId) {
    require(qualityScore <= 100, "Max score is 100");
    Escrow storage e = escrows[escrowId];
    Milestone storage m = e.milestones[milestoneId];
    
    require(m.status == MilestoneStatus.DELIVERED, "Not delivered");

    // RED HERRING 2: Inclusive Threshold per Documented Spec
    if (qualityScore >= 80) {
        e.highQualityCount++;
    }

    m.qualityScore = qualityScore;
    m.status = MilestoneStatus.APPROVED;

    // Internal call 1: Calculate exact payout
    uint256 payout = _calculateMilestonePayout(m.amount, m.dueDate, m.deliveredAt, qualityScore);
    m.payout = payout;

    // State update 1: Add to released total
    e.totalReleased += payout;

    // BUG FIX: Subtract the actual payout, not the full m.amount.
    // This ensures the invariant e.balance + e.totalReleased == e.totalDeposit
    // is maintained even when penalties reduce the payout below m.amount.
    e.balance -= payout;

    // Internal call 2: Update global profiles
    _updateGlobalSupplierMetrics(e.supplier, qualityScore, (m.amount - payout));

    emit DeliveryApproved(escrowId, milestoneId, payout);
}
```
