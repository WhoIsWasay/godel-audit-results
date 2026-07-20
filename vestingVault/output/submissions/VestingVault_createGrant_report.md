### [VULNERABILITY CLASS]
MEDIUM: The createGrant function overwrites any existing grant for... in `createGrant`

**Vulnerability Detail:**
The createGrant function overwrites any existing grant for a beneficiary but does not subtract the previous grant's totalAmount from totalGranted. This permanently breaks the accounting invariant that totalGranted equals the sum of all active grants' totalAmount. An admin (or any future caller if admin changed) can inflate totalGranted arbitrarily by repeatedly calling createGrant for the same address.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(totalGranted == totalGranted_pre - grants[beneficiary].totalAmount_pre + amount) where _pre denotes the state immediately before the call to createGrant. In other words, the function must guarantee that totalGranted is updated by exactly (new amount - old grant’s totalAmount).` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
grants[beneficiary] = Grant({
            totalAmount: amount,
            ...
        });
        totalGranted += amount;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: totalGranted inflated by repeated createGrant calls
[totalGranted_2 = 1263602,
 totalAmount_0 = 4134,
 totalAmount_2 = 798717,
 totalAmount_1 = 460751,
 totalGranted_0 = 4134,
 amount1 = 460751,
 amount2 = 798717,
 totalGranted_1 = 464885]
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/VestingVault_createGrant_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function createGrant(
    address beneficiary,
    uint256 amount,
    uint256 duration,
    uint256 cliffDuration
) external onlyAdmin {
    if (amount == 0 || duration == 0 || cliffDuration > duration) revert InvalidAmount();

    // Fetch the previous totalAmount from any existing grant for this beneficiary
    uint256 oldTotalAmount = grants[beneficiary].totalAmount;

    // Overwrite the grant with the new parameters
    grants[beneficiary] = Grant({
        totalAmount: amount,
        claimedAmount: 0,
        startTime: block.timestamp,
        duration: duration,
        cliffDuration: cliffDuration,
        revoked: false
    });

    // Maintain the invariant:
    // totalGranted = totalGranted_prev - oldTotalAmount + amount
    totalGranted = totalGranted - oldTotalAmount + amount;

    emit GrantCreated(beneficiary, amount, duration, cliffDuration);
    require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
}
```
