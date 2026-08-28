# Gödel Audit Results

Public findings from Gödel, an AI-powered formal verification pipeline for 
smart contract security audits.

Gödel combines symbolic execution, Z3 theorem proving, and a multi-agent 
CEGIS (Counterexample-Guided Inductive Synthesis) loop to find and verify 
arithmetic, boundary, and invariant-violation bugs in Solidity contracts — 
with proof, not guesswork.

## How it works (short version)

For each contract function, Gödel:
1. Hunts for candidate vulnerabilities against the function's logic
2. Generates a formal property the function should satisfy
3. Attempts to prove or disprove that property using Z3 / symbolic execution
4. If a violation is found, generates a native Foundry test that reproduces 
   it on-chain — not just a theoretical counterexample, but an executable 
   proof of exploit
5. If the exploit is verified, an AI agent proposes a fix, which is re-verified 
   against the same property

A bug only makes it into `submissions/` if it survives this full loop: 
found, proven, and reproduced as a passing exploit test.

## Structure

```
<ContractName>/
├── src/              — the contract analyzed
├── logs/             — full orchestrator run logs (thread spawns,
│                        CEGIS attempts, pass/fail per function)
└── output/
    └── submissions/   — verified findings: vulnerability, proof,
                          and recommended fix
```

## Contracts audited so far

### Synthetic Benchmarks (planted bugs)
- `daoTreasuryManager`
- `discountLiquidityPool`
- `enterpriseSupply-ChainEscrowManager`
- `globalPayrollWithholdingManager`
- `subscriptionBillingProration`
- `vestingVault`
- `collateralizeDebtPosition`

### Real Competitive Audits (Code4rena)
- `PoolTogetherV3/` — PoolTogether V3 yield sources (Code4rena 2021-06)
  - `IdleYieldSource` — Found H-01: wrong variable in redeemToken (forge-confirmed)
  - `YearnV2YieldSource` — Found H-02: inverted subtraction in _withdrawFromVault (Z3-proven) + 2 precision-loss bugs in share conversion (forge-confirmed, not in original C4 report)

## Status

**Synthetic benchmarks:** 19/23 planted bugs found (82.6% catch rate) across 7 contracts.

**Real competitive audits:** 4 findings across 2 contracts from the Code4rena 2021-06 PoolTogether V3 contest. 2 match known high-severity findings from the original human audit (H-01, H-02); 2 precision-loss bugs in YearnV2YieldSource share conversion were independently identified and not in the original C4 report.

## Contact

- Email: [wasay.godel@gmail.com](mailto:wasay.godel@gmail.com)
- LinkedIn: [Abdul Wasay](https://www.linkedin.com/in/abdul-wasay-a9647b282/)