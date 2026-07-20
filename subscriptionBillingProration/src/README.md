# Subscription Billing Manager - Formal Verification Benchmark

## Protocol Purpose
The `SubscriptionBillingManager` is a centralized SaaS protocol contract that handles recurring billing, loyalty-based discount tiers, and prorated cancellations. It utilizes complex math to track user payment completeness and strict array manipulation for administrative analytics.

## Core Invariants
The formal verification tool must prove or disprove the following mathematical invariants using symbolic execution of the smart contract's functions in isolation:

1. **Payment Completeness State**
   In `payInvoice`, a subscription's status must accurately reflect if it is fully paid.
   - *Property:* `sub.status == Status.PAID` if and only if `sub.totalPaid >= sub.expectedTotal`.

2. **Refund Precision (No Intermediary Loss)**
   In `cancelAndRefund`, the mathematical refund amount must perfectly match a single-step algebraic equivalent for a 360-day financial year to prevent significant value truncation.
   - *Property:* `refundAmount == (annualRate * daysRemaining) / 360`.

3. **Loyalty Tier Accuracy**
   In `getLoyaltyDiscount`, the returned discount tier must strictly adhere to the defined duration thresholds, granting discounts only when the requirement is fully met.
   - *Property:* `getLoyaltyDiscount(monthsActive) == 0` when `monthsActive < 6`.

4. **Analytics Overflow Safety**
   In `calculateTotalWatchTime`, the aggregation of session durations must not overflow `type(uint256).max` under any valid configuration of the input array.
   - *Property:* Function must not revert due to arithmetic overflow inside the `unchecked` block given the `require` preconditions.

5. **Batch Refund Solvency**
   In `refundBatch`, the deduction of penalties from the total must never trigger an arithmetic underflow.
   - *Property:* `total >= penalty` must hold true for any bounded symbolic array input.

## Expected Function Behaviors
- `createSubscription`: Initializes a subscription mapping with standard parameters.
- `payInvoice`: Updates user payment balances and determines active/paid status.
- `cancelAndRefund`: Terminates the subscription and calculates the time-weighted refund.
- `getLoyaltyDiscount`: Reads the configured tier arrays and returns the proper bps discount.
- `applyLoyaltyDiscount`: Writes the calculated discount to the subscription's `expectedTotal`.
- `pauseSubscription` / `resumeSubscription`: Toggles between ACTIVE and PAUSED states.
- `calculateTotalWatchTime`: Pure analytic iteration summing bounded durations.
- `refundBatch`: Pure administrative iteration summing totals and proportional penalties.

## Out of Scope Assumptions
- **Reentrancy:** Cross-contract reentrancy attacks are out of scope. 
- **Access Control:** Malicious owner or access compromise is out of scope.
- **Oracle / Timestamp Manipulation:** MEV, front-running, and block timestamp manipulation are strictly out of scope. 
- **Gas Limitations:** Out-of-gas (OOG) reverts on large arrays are not considered bugs for this benchmark.

## Scope Note for Verification Tooling
This benchmark is scoped strictly to **pure arithmetic, array manipulation, and state-logic properties**. The tooling should be able to evaluate the constraints strictly by mapping the Solidity AST to an SMT solver (e.g., Z3) and evaluating symbolic inputs against the Core Invariants in a single-function isolation context.