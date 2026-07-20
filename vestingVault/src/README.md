# VestingVault

## Protocol Purpose

`VestingVault` lets an admin create linear token vesting grants for beneficiaries.
Tokens vest linearly from `startTime` to `startTime + duration`, gated by an
initial `cliffDuration` during which nothing is claimable. The admin may revoke
a grant at any time, freezing the beneficiary's entitlement at whatever has
vested so far and reclaiming the rest.

## Core Invariants

1. **Linear Vesting Invariant**: For any beneficiary and any timestamp `t` such
   that `startTime + cliffDuration <= t < startTime + duration`, the vested
   amount must equal `totalAmount * (t - startTime) / duration` — i.e. vesting
   scales linearly and continuously with elapsed time across the *entire*
   `[cliff, duration]` window, not just at the cliff boundary. At `t >=
   startTime + duration`, vested amount must equal `totalAmount` exactly.

2. **Claim Monotonicity Invariant**: `claimedAmount` must never exceed
   `vestedAmount(beneficiary)` at any point in time, and a `claim()` call must
   never transfer more tokens than `vestedAmount(beneficiary) - claimedAmount`
   at the time of the call.

3. **Global Accounting Invariant**: `totalGranted` must always equal the sum of
   `totalAmount` across all grants (accounting for `revoke` reductions), and
   `totalClaimed` must always equal the sum of `claimedAmount` across all
   grants.

4. **Revocation Non-Negativity Invariant**: `revoke` must never cause
   `returnedAmount` to underflow or exceed the original `totalAmount`, and the
   beneficiary's post-revocation entitlement (`g.totalAmount` after revoke)
   must never be less than what they had already claimed.

## Expected Function Behaviors

* `createGrant`: Admin-only. Registers a new linear grant and pulls the full
  granted amount into the vault upfront.
* `claim`: Transfers all currently vested-but-unclaimed tokens to the caller.
  Reverts before the cliff has elapsed.
* `revoke`: Admin-only. Locks a beneficiary's grant to their currently vested
  amount and returns the unvested remainder to the admin.
* `vestedAmount`: Pure view computation of total vested tokens at the current
  block timestamp, per the Linear Vesting Invariant above.

## Out of Scope Assumptions

* **Token Specifics**: The underlying token is a vanilla, fully compliant
  ERC20 with no fee-on-transfer, rebasing, or transfer hooks.
* **Reentrancy**: Not in scope for this benchmark — assume `transfer` and
  `transferFrom` cannot reenter. Do not flag Checks-Effects-Interactions
  ordering as a finding; that class of bug is intentionally out of scope for
  this test set.
* **Timestamp Manipulation**: Assume `block.timestamp` is trustworthy and not
  adversarially manipulated by miners/validators within this benchmark.
* **Access Control on `admin`**: Assume `admin` is set correctly at
  construction and is never compromised; do not flag the lack of
  `admin` transfer/renouncement functionality as a finding.

## Scope Note for Verification Tooling

This benchmark is intentionally scoped to **pure arithmetic and state-logic
properties provable by an SMT solver (Z3)** — not control-flow ordering,
reentrancy, or access-control bugs. Every bug in this contract, if present, is
expressible as a violation of one of the four invariants above using only the
function's internal arithmetic and storage reads/writes.
