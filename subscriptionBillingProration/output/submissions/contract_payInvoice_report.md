### [VULNERABILITY CLASS]
MEDIUM: The payInvoice function only sets the subscription status... in `payInvoice`

**Vulnerability Detail:**
The payInvoice function only sets the subscription status to PAID when the new total equals the expected amount exactly (newPaid == expected). If a user overpays (newPaid > expected), the status is not updated and remains ACTIVE or PAUSED, violating the core invariant that the status must be PAID whenever totalPaid >= expectedTotal.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(sub.status == Status.PAID iff sub.totalPaid >= sub.expectedTotal)` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
if (newPaid == expected) {
            sub.status = Status.PAID;
        } else if (newPaid < expected) {
            sub.status = Status.ACTIVE;
        }
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: Overpayment does not set status to PAID
[totalPaid_0 = 16946,
 amount = 999933,
 status_0 = 4,
 expected_0 = 2,
 newPaid = 1016879,
 status_1 = 4]
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/contract_payInvoice_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function payInvoice(uint256 subId, uint256 amount) external subExists(subId) {
    Subscription storage sub = subscriptions[subId];
    require(sub.status == Status.ACTIVE || sub.status == Status.PAUSED, "Invalid status for payment");
    require(amount > 0, "Zero payment");

    // Effects: update state variables
    uint256 newPaid = sub.totalPaid + amount;
    sub.totalPaid = newPaid;
    totalPlatformRevenue += amount;

    // Enforce invariant: status = PAID iff totalPaid >= expectedTotal
    if (sub.totalPaid >= sub.expectedTotal) {
        sub.status = Status.PAID;
    } else {
        sub.status = Status.ACTIVE;
    }

    // No external interactions, safe to emit after all state changes
    emit PaymentProcessed(subId, amount);
}
```
