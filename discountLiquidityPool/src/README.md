# Discount Liquidity Pool - Formal Verification Benchmark

## Protocol Purpose
The `DiscountLiquidityPool` is a simplified Automated Market Maker (AMM) that allows users to supply paired tokens and receive LP shares. To incentivize large traders, the pool implements a dynamic withdrawal fee structure where the fee percentage decreases as the volume of tokens being withdrawn increases. 

## Core Invariants
The formal verification tool must prove or disprove the following mathematical invariants using symbolic execution of the smart contract's functions:

1. **Precision Conservation (Proportionality)**
   In `removeLiquidity`, the underlying calculation for `baseAmountA` and `amountB` must correctly represent the user's share of the reserves without suffering from catastrophic truncation. 
   - *Property:* `baseAmountA == (reserveA * lpAmount) / totalLpSupply`

2. **Fee Monotonicity**
   In `calculateWithdrawalFee`, the absolute fee amount charged must never decrease when the withdrawal amount increases. 
   - *Property:* For any arbitrary inputs `x` and `y` where `x <= y`, it must hold true that `calculateWithdrawalFee(x) <= calculateWithdrawalFee(y)`.

3. **Arithmetic Safety (No Overflow)**
   In `addLiquidity`, the calculation of the LP tokens to mint must not overflow the 256-bit integer limit under allowed operational constraints.
   - *Property:* `total = amountA + amountB` must not overflow `type(uint256).max` given the state preconditions.

## Expected Function Behaviors
- `addLiquidity`: Accepts Token A and Token B, mints proportional LP tokens based on an unweighted sum model.
- `removeLiquidity`: Burns LP tokens, calculates the proportional share of reserves, deducts the volume-based fee, and returns tokens to the user.
- `calculateWithdrawalFee`: Pure math function returning the absolute fee to deduct based on a tiered basis-point discount.

## Out of Scope Assumptions
- **Reentrancy:** Cross-contract reentrancy attacks are out of scope. Treat `IERC20.transfer` and `transferFrom` as trusted state transitions.
- **Access Control:** Malicious owner or access compromise is out of scope.
- **Oracle / Timestamp Manipulation:** MEV, front-running, and timestamp manipulation are strictly out of scope. 
- **Gas Limitations:** Out-of-gas reverts are not considered bugs for this benchmark.

## Scope Note for Verification Tooling
This benchmark is scoped strictly to **pure arithmetic, accounting logic, and state-logic properties**. The tooling should be able to evaluate the constraints strictly by mapping the Solidity AST to an SMT solver (e.g., Z3) and evaluating symbolic inputs against the Core Invariants in a single-function isolation context.