### [VULNERABILITY CLASS]
HIGH: Incorrect denominator (365) used in vesting calculation treats... in `calculateVestedOptions`

**Vulnerability Detail:**
Incorrect denominator (365) used in vesting calculation treats timeElapsed in seconds as days, causing options to vest approximately 86,400 times faster than the intended 1-year linear schedule.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(vested == min(totalOptions, (totalOptions * timeElapsed) / 31536000))` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
uint256 vested = (totalOptions * timeElapsed) / 365;
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: Vesting calculation allows vested > totalOptions
[totalOptions = 782184,
 currentTimestamp = 86844705986562962583629769705679673142029551546190545253071087257883236578601,
 startTimestamp = 86844705986562962583629769705679673142029551546190545253071087257883235581952,
 timeElapsed = 996649,
 vested = 2135788771]
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/contract_calculateVestedOptions_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function calculateVestedOptions(uint256 totalOptions, uint256 startTimestamp, uint256 currentTimestamp) public pure returns (uint256) {
    require(currentTimestamp >= startTimestamp, "Time error");
    uint256 timeElapsed = currentTimestamp - startTimestamp;
    
    // Corrected denominator: seconds in a non-leap year (365 days)
    uint256 vested = (totalOptions * timeElapsed) / 31536000;
    
    if (vested > totalOptions) {
        vested = totalOptions;
    }
    
    return vested;
}
```
