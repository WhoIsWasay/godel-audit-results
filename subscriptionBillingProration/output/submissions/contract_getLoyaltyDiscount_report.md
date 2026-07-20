### [VULNERABILITY CLASS]
HIGH: The function incorrectly grants a discount for any... in `getLoyaltyDiscount`

**Vulnerability Detail:**
The function incorrectly grants a discount for any monthsActive > 0 because the threshold comparison uses strict greater-than, causing even a single active month to qualify for the first discount tier (5%), violating the invariant that no discount should be applied for monthsActive < 6.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(getLoyaltyDiscount(monthsActive) == 0) when monthsActive < 6` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
if (monthsActive > monthThresholds[i]) {
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: Counterexample exists
[monthsActive = 4]
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/contract_getLoyaltyDiscount_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function getLoyaltyDiscount(uint256 monthsActive) public view returns (uint16) {
    uint256 tierIndex = 0;

    // Scan through the 5 tiers to find the highest eligible bracket
    for (uint256 i = 0; i < 5; i++) {
        if (monthsActive >= monthThresholds[i]) {
            tierIndex = i;
        }
    }

    // Clamp to maximum available tier to prevent out-of-bounds reads
    if (tierIndex >= 5) {
        tierIndex = 4;
    }

    return discountTiers[tierIndex];
}
```
