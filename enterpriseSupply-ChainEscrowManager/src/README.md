# Supply Chain Escrow Manager - Formal Verification Benchmark

## Protocol Purpose
The `SupplyChainEscrowManager` is an enterprise-grade protocol for locking buyer funds, validating multi-stage supplier deliveries, and dispersing risk-adjusted payouts. It incorporates complex internal state management, mathematical penalty combinations for delayed/subpar deliverables, and iterative progress tracking.

## Core Invariants
The formal verification tool must prove or disprove the following mathematical invariants using symbolic execution of the smart contract's functions in isolation:

1. **Penalty Compounding Integrity**
   In `_calculateMilestonePayout`, if a delivery is both late and of poor quality, the mathematical reductions must be fully compounded (subtracted) against the base payout. 
   - *Property:* `adjustedPayout == basePayout - qualityPenalty - delayPenalty`.

2. **Valid Milestone Initialization Bound**
   In `submitDelivery`, a supplier must only be able to interact with explicitly initialized milestones created during setup. Access beyond initialized length is strictly forbidden.
   - *Property:* The `status` mapping assignment must be strictly unreachable for any `milestoneId >= e.milestoneCount`.

3. **Conservation of Escrow Balance**
   In `approveDelivery`, assuming no prior arbitration fees, the total amount of money released to the supplier plus the remaining held balance must exactly equal the initial deposit.
   - *Property:* `e.balance + e.totalReleased == e.totalDeposit` must remain `SAT` post-transaction.

4. **Weighted Progress Ceiling**
   In `calculateTotalWeightedProgress`, the returned average progress rating must mathematically never exceed the maximum valid `qualityScore` of 100 under any loop configuration.
   - *Property:* `calculateTotalWeightedProgress(escrowId) <= 100`.

## Expected Function Behaviors
- `createEscrow`: Initializes parent escrow structure and mappings.
- `addMilestones`: Batch-adds configurations, updating total deposit and length tracking.
- `fundEscrow`: Locks deposit value into the active balance.
- `submitDelivery`: Transitions milestone state to DELIVERED and logs the timestamp.
- `approveDelivery`: Finalizes approval, triggers internal penalty math, and updates balances.
- `_calculateMilestonePayout`: Internal helper containing sequential branch math for deductions.
- `_updateGlobalSupplierMetrics`: Internal helper for global metric aggregations.
- `getMilestoneComplexityBound`: Pure view returning an analytical multiplier.
- `calculateTotalWeightedProgress`: View iterating over mappings to calculate a weighted average.
- `distributeArbitratorFees`: Loops over disputed milestones and mutates storage balances directly.
- `refundRemainingToBuyer`: Zeros out balance and cancels the escrow.
- `raiseDispute`: Mutates statuses to IN_DISPUTE.

## Out of Scope Assumptions
- **Reentrancy & Cross-Contract:** Not applicable. Treat state transitions as atomic.
- **Access Control:** Malicious `msg.sender` manipulation or compromised admin keys are out of scope.
- **Oracle / Timestamp:** MEV and block timestamp manipulations are out of scope. 
- **Gas / DoS:** Out-of-gas reverts on loops are strictly out of scope.

## Scope Note for Verification Tooling
This benchmark is scoped strictly to **pure arithmetic, struct-mapping access boundaries, correct unrolling of loop denominators, and complex local variable tracing**. Tooling must evaluate constraints by mapping the Solidity AST to an SMT solver (e.g., Z3) to check properties at isolated function boundaries.