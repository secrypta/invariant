# RESULT - poc-ctoken (Venus donation / exchange-rate inflation), TIER-1 full-blind

Campaign: Foundry invariant, **256 runs / depth 64** (`foundry.toml`), inside a sandboxed Docker container.
Verdict line / SLACK = **4·depth = 256** (catalog §"Why SLACK = 4·depth": a proven ceiling on rounding noise,
not a theft threshold). The harness (`test/` + `src/` stubs) is the **verbatim generator output** of `invgen scan`.

## Verdict ✅
The generator-produced harness re-discovers the donation / exchange-rate-inflation bug on the verbatim vulnerable
Venus commit and stays silent on the verbatim fixed commit. Discriminator **CT1 (attacker-no-profit)**:
**FAIL on VULN @9c6467db**, **PASS on FIX @PR#664**. `detect` = `ctoken` **blind** on both sides.

| Invariant | Role | VULN @9c6467db | FIX @PR#664 |
|-----------|------|----------------|-------------|
| CT1 attacker-no-profit | discriminator (gate) | **FAIL** | **PASS** |
| CT3 solvency | control | PASS | PASS |
| CT4 redeem-honored | control | PASS | PASS |
| CT5 round-trip overshoot | donation-class detector | FAIL (donation-exposure) | PASS |

## Quantitative evidence (in-place `forge test` on this packaged project; `solc 0.8.25`, seed `0x4136`)
Both sides compile (51 files, `Compiler run successful`) from the vendored sources alone.
- **VULN** (`default` profile) - `invariant_CT1_attackerNoProfit` **FAIL**: attacker wealth exceeds
  `fundedAttacker + SLACK` - `1356643972625866705475134 > 1356643972625866705473847` (profit over funded ≈ 1543
  wei ≫ SLACK=256). Found deterministically (runs: 1, calls: 64). Controls hold non-vacuously:
  `CT3_solvency` / `CT4_redeemHonored` / `CT5_noRoundTripProfit` **PASS** at 256 runs × 16384 calls each → the
  bug is caught by the gate alone, with no false control break. Suite: 3 passed, 1 failed.
- **FIX** (`fix` profile) - **all four PASS** (`CT1`/`CT3`/`CT4`/`CT5`), 256 runs × 16384 calls each (non-vacuous).
  Suite: 4 passed, 0 failed. PR #664's internal-cash accounting removes the inflatable exchange-rate exposure, so
  no in-rounding theft is reachable.

## How to reproduce
See [`README.md`](README.md) → "How to run": `forge test --match-contract VBep20Invariant` (default = VULN) and
`FOUNDRY_PROFILE=fix forge test --match-contract VBep20Invariant` (= FIX), inside `invgen-tools:1`.

## Honesty
- **TIER-1 full-blind**: both sides are verbatim third-party source at pinned historical commits (no reconstruction);
  provenance (commits, licenses, SPDX) in [`PROVENANCE.md`](PROVENANCE.md). `detect` = `ctoken` blind on both sides.
- The harness (`test/` + `src/` stubs) is the verbatim output of `invgen scan` - not hand-written. The numbers above
  are this packaged project's own in-place `forge test` both-run (not a copy of the scan log).
- Boundaries: answer-agnostic (invariants read public getters, never the engine's internal cash); oracle/off-chain
  out of scope; `reach` counted by Handler calls actually executed.
