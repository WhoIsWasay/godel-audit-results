### [VULNERABILITY CLASS]
HIGH: The withdrawal balance delta is inverted. After vault.withdraw()... in `_withdrawFromVault`

**Vulnerability Detail:**
The withdrawal balance delta is inverted. After vault.withdraw() transfers the redeemed tokens into this contract, token.balanceOf(address(this)) increases, so currentBalance_new = previousBalance_old + receivedAmount. The expression previousBalance_old - currentBalance_new is therefore negative; under Solidity 0.8 checked arithmetic it underflows and reverts. Thus every non-zero successful vault withdrawal causes _withdrawFromVault to revert, permanently preventing withdrawals.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(currentBalance_new > previousBalance_old => _withdrawFromVault_return == currentBalance_new - previousBalance_old);` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
return previousBalance - currentBalance;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: Withdrawal balance delta is inverted, causing underflow revert
[receivedAmount = 655359,
 previousBalance = 999934,
 currentBalance = 1655293]
Concrete counterexample assignments: currentBalance=1655293, previousBalance=999934, receivedAmount=655359
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/YearnV2YieldSource__withdrawFromVault_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function _withdrawFromVault(uint amount) internal returns (uint256) {
    uint256 yShares = _tokenToYShares(amount);
    uint256 previousBalance = token.balanceOf(address(this));
    // we accept losses to avoid being locked in the Vault (if losses happened for some reason)
    if(maxLosses != 0) {
        vault.withdraw(yShares, address(this), maxLosses);
    } else {
        vault.withdraw(yShares);
    }
    uint256 currentBalance = token.balanceOf(address(this));

    return currentBalance - previousBalance;
}
```
