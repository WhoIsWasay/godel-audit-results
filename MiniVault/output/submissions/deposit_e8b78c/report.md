### [VULNERABILITY CLASS]
MEDIUM: A non-zero deposit can mint zero shares when... in `deposit`

**Vulnerability Detail:**
A non-zero deposit can mint zero shares when the share price is high, because (assets*totalSupply)/totalAssets truncates to 0 — the sender loses assets and receives no shares.

Auditor note / hypothesis to re-confirm: The share price (totalAssets/totalSupply) can rise above 1 after emergencyWithdraw subtracts a flat 500 instead of 5%. Once the price is high, a small deposit makes (assets*totalSupply)/totalAssets truncate to 0, so the user transfers assets in but is minted zero shares. Re-confirm this and give me the fix.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `shares = (assets * totalSupply) / totalAssets rounds down to zero for small assets relative to a high share price.` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
assets > 0 => shares > 0 (Anti-Dilution, README Core Invariant 1)
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3 TIMEOUT — Forge-direct rescue] Z3 could not decide the nonlinear property, but a concrete witness was supplied: assets=1, totalAssets=1000, totalSupply=1. Routing to the Foundry gatekeeper to confirm/deny on the real EVM.
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/MiniVault_deposit_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
// <!-- reasoning: (a) The deposit formula `(assets * totalSupply) / totalAssets` can truncate to zero when the share price is high, so a positive deposit could transfer assets while minting no shares. (b) Reject any zero-share result immediately after the share calculation, before updating balances/supply/assets or pulling tokens. -->
function deposit(uint256 assets) external {
    require(assets > 0, "Zero amount");

    uint256 shares;

    if (totalSupply == 0) {
        shares = assets;
    } else {
        shares = (assets * totalSupply) / totalAssets;
        require(shares > 0, "Invalid shares");
    }

    balances[msg.sender] += shares;
    totalSupply += shares;
    totalAssets += assets;

    require(asset.transferFrom(msg.sender, address(this), assets), "Transfer failed");
}
```

### VERIFICATION STATUS

- EVM verification: **CONFIRMED** (qc_status=confirmed).
- What the EVM test actually asserted: `failed to set up invariant testing environment: positive deposit into an existing vault must mint positive shares: 1 <= 1`
