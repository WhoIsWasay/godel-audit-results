### [VULNERABILITY CLASS]
HIGH: The withdrawal share-burn uses floor division: sharesToBurn =... in `withdraw`

**Vulnerability Detail:**
The withdrawal share-burn uses floor division: sharesToBurn = (assetsRequested * totalSupply) / totalAssets. When assetsRequested * totalSupply < totalAssets, sharesToBurn truncates to 0 and the subsequent require(balances[msg.sender] >= sharesToBurn) passes even for a zero-share account. A caller can therefore extract assets while burning zero shares, violating the invariant assetsRequested > 0 => sharesToBurn > 0.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(assetsRequested > 0 && totalAssets_old > 0 => (assetsRequested * totalSupply_old) / totalAssets_old > 0)` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
uint256 sharesToBurn = (assetsRequested * totalSupply) / totalAssets; require(balances[msg.sender] >= sharesToBurn, "Insufficient balance");
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
SANITY: sat
BUG FOUND: [balances__S_new = 0,
 totalSupply__new = 0,
 totalAssets__new = 2,
 balances__GEN_new = 0,
 msg_sender = 0,
 l_sharesToBurn = 0,
 msg_value = 0,
 balances__S = 0,
 balances__old = 0,
 a_assetsRequested = 2,
 balances__GEN = 0,
 balances__new = 0,
 totalAssets__old = 4,
 totalSupply__old = 1,
 block_timestamp = 0,
 div0 = [else -> 0],
 mod0 = [else -> 0]]
Concrete counterexample assignments: a_assetsRequested=2, balances__GEN=0, balances__GEN_new=0, balances__S=0, balances__S_new=0, balances__new=0, balances__old=0, block_timestamp=0, l_sharesToBurn=0, msg_sender=0, msg_value=0, totalAssets__new=2, totalAssets__old=4, totalSupply__new=0, totalSupply__old=1
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/Contract_withdraw_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
// <!-- reasoning: (a) floor division in sharesToBurn truncates to 0 when assetsRequested * totalSupply < totalAssets, allowing a zero-share caller to withdraw assets without burning shares; (b) the vulnerable line is the sharesToBurn computation and the subsequent balance check; (c) the fix adds a strict sharesToBurn > 0 requirement plus guards against an empty/unbalanced vault, preventing any asset extraction with zero share burn. -->
function withdraw(uint256 assetsRequested) external {
    require(assetsRequested > 0, "Zero amount");
    require(totalAssets > 0, "No assets");
    require(totalSupply > 0, "No supply");
    require(assetsRequested <= totalAssets, "Insufficient assets");

    uint256 sharesToBurn = (assetsRequested * totalSupply) / totalAssets;
    require(sharesToBurn > 0, "Shares round to zero");
    require(balances[msg.sender] >= sharesToBurn, "Insufficient balance");

    balances[msg.sender] -= sharesToBurn;
    totalSupply -= sharesToBurn;
    totalAssets -= assetsRequested;

    require(asset.transfer(msg.sender, assetsRequested), "Transfer failed");
}
```

### VERIFICATION STATUS

- EVM verification: **CONFIRMED** (qc_status=confirmed).
- What the EVM test actually asserted: `withdraw succeeded without burning the outstanding share: 1 != 0`
