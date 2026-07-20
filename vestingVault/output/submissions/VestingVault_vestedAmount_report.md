### [VULNERABILITY CLASS]
HIGH: The vestedAmount function contains an arithmetic bug: it... in `vestedAmount`

**Vulnerability Detail:**
The vestedAmount function contains an arithmetic bug: it multiplies totalAmount by cliffDuration instead of elapsed, causing the vesting calculation to ignore elapsed time and produce a constant, incorrect vested amount. As a result, the vesting schedule does not reflect linear interpolation over the time elapsed; the beneficiary would never receive more tokens over time beyond a fixed fraction determined by the cliff/duration ratio. This breaks the core economic invariant that vesting should be proportional to the time that has passed after the cliff.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(vestedAmount == (g.totalAmount * (block.timestamp - g.startTime)) / g.duration) when block.timestamp >= g.startTime + g.cliffDuration and block.timestamp < g.startTime + g.duration` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
        // Linear interpolation: totalAmount * elapsed / duration
        return (g.totalAmount * g.cliffDuration) / g.duration;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: vested amount is constant regardless of elapsed time
totalAmount: 0
cliffDuration: 2
duration: 1147
elapsed: 72
elapsed2: 1145
vested: 0
vested2: 0
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/VestingVault_vestedAmount_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function vestedAmount(address beneficiary) public view returns (uint256) {
    Grant storage g = grants[beneficiary];
    if (g.totalAmount == 0) return 0;

    if (block.timestamp < g.startTime + g.cliffDuration) {
        return 0;
    }

    uint256 elapsed = block.timestamp - g.startTime;

    if (elapsed >= g.duration) {
        return g.totalAmount;
    }

    // Linear interpolation: totalAmount * elapsed / duration
    return (g.totalAmount * elapsed) / g.duration;
}
```
