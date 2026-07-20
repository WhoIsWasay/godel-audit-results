### [VULNERABILITY CLASS]
HIGH: terminateEmployee sets the employees optionsGranted using calculateVestedOptions, which... in `terminateEmployee`

**Vulnerability Detail:**
terminateEmployee sets the employee's optionsGranted using calculateVestedOptions, which erroneously uses 365 as the denominator instead of 31,536,000 seconds for a one-year vesting period. This causes the cap on vested options to be reached instantly or after a tiny fraction of the intended vesting period, granting the employee significantly more options than they should be entitled to and violating the vesting timeline fidelity.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `The final value of emp.optionsGranted must equal (originalOptionsGranted * (block.timestamp - emp.startDate)) / 31536000, capped at originalOptionsGranted, ensuring linear vesting over one year (31,536,000 seconds).` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
uint256 finalVested = calculateVestedOptions(emp.optionsGranted, emp.startDate, block.timestamp);
        emp.optionsGranted = finalVested; // Revoke unvested
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND:
totalOptions = 700381
startTimestamp = 458752
currentTimestamp = 458819
timeElapsed = 67
vested (buggy) = 128563
correctVested = 1
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/contract_terminateEmployee_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function terminateEmployee(address wallet) external onlyAdmin employeeExists(wallet) {
    Employee storage emp = employees[wallet];
    require(emp.status != EmployeeStatus.TERMINATED, "Already terminated");

    emp.status = EmployeeStatus.TERMINATED;

    // Final options vesting calculation locked at termination
    // Correct vesting formula: linear over 1 year (31,536,000 seconds)
    uint256 timeElapsed = block.timestamp - emp.startDate;
    uint256 finalVested = (emp.optionsGranted * timeElapsed) / 31536000;
    if (finalVested > emp.optionsGranted) {
        finalVested = emp.optionsGranted;
    }
    emp.optionsGranted = finalVested; // Revoke unvested
}
```
