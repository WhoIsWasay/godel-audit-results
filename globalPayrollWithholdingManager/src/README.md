# Global Payroll Manager - Formal Verification Benchmark

## Protocol Purpose
The `GlobalPayrollManager` is an enterprise-level smart contract designed to manage complex employee compensation. It calculates multi-tier progressive tax brackets, computes exact time-weighted PTO accruals and stock option vesting, and applies diverse additions and deductions (including executive perks and loan installments) to finalize net paychecks.

## Core Invariants
The formal verification tool must prove or disprove the following mathematical invariants using symbolic execution of the smart contract's functions in strict isolation:

1. **Progressive Tax Accuracy**
   In `calculateTax`, the returned `totalTax` must exactly equal the mathematical piecewise sum of all applicable tax brackets for any given `grossSalary`.
   - *Property:* For `grossSalary > 200000e18`, `totalTax == 5000e18 + 10000e18 + 20000e18 + ((grossSalary - 200000e18) * 30 / 100)`.

2. **Linear Time-Weighted Accrual**
   In `calculateAccruedPTO`, the final payout must precisely match the raw time difference in milliseconds multiplied by the rate, without truncation, for any valid date range.
   - *Property:* `ptoPayout == ((endDate - startDate) * 1000) * ratePerMs`.

3. **Vesting Timeline Fidelity**
   In `calculateVestedOptions`, the number of vested options must reflect an exact 1-year (31,536,000 seconds) linear vesting curve.
   - *Property:* `vested == (totalOptions * (currentTimestamp - startTimestamp)) / 31536000` (capped at `totalOptions`).

4. **Loan Deduction Identity**
   In `calculateFinalPaycheck`, if an employee has an outstanding loan and sufficient net pay, the function must mathematically reduce their final net pay by exactly the `LOAN_INSTALLMENT` amount.
   - *Property:* If `hasOutstandingLoan == true` and initial `net > LOAN_INSTALLMENT`, then `finalNet < initialNet`.

## Expected Function Behaviors
- `fundPayroll`: Adds liquidity to the master payroll fund.
- `addEmployee`: Registers a new employee struct with base compensation rules.
- `calculateTax`: Pure piecewise function for marginal tax rates.
- `calculateAccruedPTO`: Pure math for converting timestamps to value.
- `calculateVestedOptions`: Pure time-ratio calculation for stock equity.
- `calculateFinalPaycheck`: Reconciles branching additions and deductions.
- `computeTieredBonus`: Recursive helper tracking multi-level rewards.
- `processPayroll`: Main entry point computing all math and deducting from the vault.
- `processPayrollBatch`: Iterates `processPayroll` over an array of addresses.

## Out of Scope Assumptions
- **Reentrancy & Cross-Contract:** Not applicable. Treat state transitions as atomic.
- **Access Control:** Malicious `msg.sender` manipulations are out of scope.
- **Cross-Function State:** Bugs requiring a specific order of multi-function calls are out of scope.
- **Oracle / Timestamp:** Block timestamp manipulations are out of scope. 
- **Gas / DoS:** Out-of-gas reverts on loops are strictly out of scope.

## Scope Note for Verification Tooling
This benchmark targets **pure arithmetic, logical branching combinations, type-casting safety, and order of operations**. The tooling must evaluate constraints by mapping the Solidity AST to an SMT solver (e.g., Z3) to check properties at isolated single-function boundaries. **All conditional branches and deeply nested logic paths within a single function MUST be fully explored.**