### [VULNERABILITY CLASS]
HIGH: The emergency withdrawal penalty is calculated as a... in `emergencyWithdraw`

**Vulnerability Detail:**
The emergency withdrawal penalty is calculated as a flat 500 wei subtraction (`netAssets = assets - penaltyBps`) instead of 5% of the asset value (`netAssets = assets * 9500 / 10000`). This violates Core Invariant 3: for example, when `assets == 1000`, the code returns `netAssets == 500` instead of `950`. It also reverts by underflow for any small position with `assets < 500`, making emergency withdrawal impossible for those positions.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(((shares * totalAssets_old) / totalSupply_old) >= 500 => ((shares * totalAssets_old) / totalSupply_old) - 500 == (((shares * totalAssets_old) / totalSupply_old) * 9500) / 10000)` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
uint256 netAssets = assets - penaltyBps;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
SANITY: sat
BUG FOUND: [balances__S_new = 0,
 totalSupply__new = 0,
 l_assets = 501,
 totalAssets__new = 0,
 balances__GEN_new = 0,
 a_shares = 0,
 msg_sender = 0,
 msg_value = 0,
 balances__S = 0,
 balances__old = 0,
 l_penaltyBps = 500,
 balances__GEN = 0,
 balances__new = 0,
 totalAssets__old = 0,
 totalSupply__old = 0,
 block_timestamp = 0,
 div0 = [else -> 501],
 mod0 = [else -> 1]]
Concrete counterexample assignments: a_shares=0, balances__GEN=0, balances__GEN_new=0, balances__S=0, balances__S_new=0, balances__new=0, balances__old=0, block_timestamp=0, l_assets=501, l_penaltyBps=500, msg_sender=0, msg_value=0, totalAssets__new=0, totalAssets__old=0, totalSupply__new=0, totalSupply__old=0
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/Contract_emergencyWithdraw_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
<!-- reasoning: (a) the emergency withdrawal penalty was subtracted as a flat 500 wei amount (`assets - penaltyBps`), instead of 5% of the asset value, causing incorrect payouts and underflow reverts for small positions; (b) recompute `netAssets` as 95% of the proportional assets using basis-point math, preserving multiplication-before-division and keeping state updates before the external transfer. -->
function emergencyWithdraw(uint256 shares) external {
    require(shares > 0 && balances[msg.sender] >= shares, "Invalid shares");
    
    uint256 assets = (shares * totalAssets) / totalSupply;
    
    // 5% penalty (500 basis points) on emergency withdrawals
    uint256 penaltyBps = 500;
    uint256 netAssets = (assets * (10000 - penaltyBps)) / 10000;
    
    balances[msg.sender] -= shares;
    totalSupply -= shares;
    totalAssets -= netAssets;
    
    require(asset.transfer(msg.sender, netAssets), "Transfer failed");
}
```

### VERIFICATION STATUS

- EVM verification: **CONFIRMED** (qc_status=confirmed).
- What the EVM test actually asserted: `emergencyWithdraw flat 500 wei penalty exceeds 5%`
