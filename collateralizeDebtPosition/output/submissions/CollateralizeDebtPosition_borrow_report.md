### [VULNERABILITY CLASS]
HIGH: The origination fee arithmetic uses floor division before... in `borrow`

**Vulnerability Detail:**
The origination fee arithmetic uses floor division before multiplication, causing the fee to be zero for any borrowAmount < 10000. This violates the Fee Proportionality Invariant that fee must equal 0.5% of borrowAmount.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(originationFee == (borrowAmount * 50) / 10000)` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
uint256 originationFee = (borrowAmount / 10000) * 50;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: Fee calculation violates proportionality
borrowAmount = 9091
originationFee = 0
Expected fee (0.5%) = 45
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/CollateralizeDebtPosition_borrow_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function borrow(uint256 borrowAmount) external {
    require(borrowAmount > 0, "Cannot borrow 0");
    require(vaultShares[msg.sender] > 0, "No collateral");

    uint256 originationFee = (borrowAmount * 50) / 10000;
    
    debt[msg.sender] += (borrowAmount + originationFee);
    
    if (lastInterestTime[msg.sender] == 0) {
        lastInterestTime[msg.sender] = block.timestamp;
    }

    require(stablecoin.transfer(msg.sender, borrowAmount), "Transfer failed");
    emit Borrowed(msg.sender, borrowAmount, originationFee);
}
```
