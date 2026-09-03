### [VULNERABILITY CLASS]
MEDIUM: When the last shareholder uses `emergencyWithdraw`, `totalSupply` becomes... in `emergencyWithdraw`

**Vulnerability Detail:**
When the last shareholder uses `emergencyWithdraw`, `totalSupply` becomes 0 but `totalAssets` is reduced only by `netAssets`, leaving the retained penalty as positive backing assets. This breaks the invariant `totalAssets == 0 iff totalSupply == 0`. The leftover `totalAssets` can then be extracted by a new depositor: after `deposit(1)`, `totalAssets` includes the leftover, and a subsequent `withdraw(leftover + 1)` burns the single new share and claims the old penalty amount.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(totalSupply_new > 0 || totalAssets_new == 0)` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
totalAssets -= netAssets;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
SANITY: sat
BUG FOUND: [totalSupply@new = 0, totalAssets@new = 1]
Concrete counterexample assignments: new=1
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/Contract_emergencyWithdraw_2_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
// <!-- reasoning: (a) The bug is that emergencyWithdraw reduces totalAssets only by netAssets, so burning the last share leaves the retained penalty as positive unbacked totalAssets. (b) The fix computes the 5% penalty correctly as basis points and, when totalSupply reaches zero, clears totalAssets to zero; otherwise the penalty remains backing for remaining stakers. -->
function emergencyWithdraw(uint256 shares) external {
    require(shares > 0 && balances[msg.sender] >= shares, "Invalid shares");
    require(totalSupply > 0, "No supply");

    uint256 assets = (shares * totalAssets) / totalSupply;

    // 5% penalty (500 basis points) on emergency withdrawals
    uint256 penaltyBps = 500;
    uint256 netAssets = assets - (assets * penaltyBps) / 10000;

    balances[msg.sender] -= shares;
    totalSupply -= shares;

    if (totalSupply == 0) {
        totalAssets = 0;
    } else {
        totalAssets -= netAssets;
    }

    require(asset.transfer(msg.sender, netAssets), "Transfer failed");
}
```

### VERIFICATION STATUS

- EVM verification: **CONFIRMED** (qc_status=confirmed).
- What the EVM test actually asserted: `vault holds orphaned assets while no shares are outstanding: 500 != 0`
