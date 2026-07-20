### [VULNERABILITY CLASS]
HIGH: The function silently truncates `rawTokenBalance` from `uint256` to... in `castVote`

**Vulnerability Detail:**
The function silently truncates `rawTokenBalance` from `uint256` to `uint64` without a proper bounds check, causing the actual vote tally to be a modulo‑reduced value instead of the full input. For any `rawTokenBalance > 2^64 – 1` the invariant `votesFor_post == votesFor_pre + rawTokenBalance` (or the analogous `votesAgainst` variant) is broken, permanently losing voting weight.

**Impact:**
Exploitation allows breaking the protocol's core logical constraints. Specifically, the mathematical system boundary `assert(prop.votesFor == oldVotesFor + rawTokenBalance) when support == true, and assert(prop.votesAgainst == oldVotesAgainst + rawTokenBalance) when support == false.` can be violated under arbitrary input configurations as proven by symbolic and static verification boundaries.

**Proof of Concept (PoC):**
1. **Target Boundary Code:**
```solidity
prop.votesFor += uint64(rawTokenBalance);
```

2. **Mathematical / Structural Verification Log:**
```text
[Z3] Counterexample found:
BUG FOUND: Silent truncation from uint256 to uint64
[support = False,
 votesAgainst_pre = 0,
 votesFor_pre = 0,
 rawTokenBalance = 81553255926290448383]
```

3. **Validation Script Reference:**
*The absolute mathematical proof can be verified by running the automatically generated validation script saved locally at:* `output/proofs/contract_castVote_1_proof.py`

**Recommendation:**
Refactor the function scope to enforce strict ordering, boundary locks, or precision adjustments. Below is the verified remediation layout:

```solidity
function castVote(uint256 proposalId, uint256 rawTokenBalance, bool support) external proposalExists(proposalId) {
    Proposal storage prop = proposals[proposalId];
    require(prop.status == Status.PENDING, "Proposal is not pending");
    require(!hasVoted[msg.sender][proposalId], "Already voted");
    
    // Enforce that the raw token balance fits into the vote weight storage (uint64)
    require(rawTokenBalance <= type(uint64).max, "Vote weight exceeds maximum allowed");

    hasVoted[msg.sender][proposalId] = true;

    if (support) {
        prop.votesFor += uint64(rawTokenBalance);
    } else {
        prop.votesAgainst += uint64(rawTokenBalance);
    }

    emit VoteCast(proposalId, msg.sender, support, rawTokenBalance);
}
```
