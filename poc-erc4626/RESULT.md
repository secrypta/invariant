# RESULT — poc-erc4626 baseline run (2026-11-10)

Campaign: Foundry invariant, baseline **256 runs / depth 64** (`foundry.toml`), inside a
sandboxed Docker container, test offline after dependencies are fetched. Dependencies:
forge-std + openzeppelin-contracts **v5.1.0**. Verdict line: **SLACK = 4·depth = 256 wei**
(rationale — catalog §"Why SLACK = 4·depth": a proven ceiling on rounding noise, not a
theft threshold).

## Verdict ✅
The harness re-discovers the donation/inflation bug on a vulnerable target and stays silent on
a correct fix. Discriminator **I2** at SLACK=256: **FAIL on NaiveVault**, **FAIL on
OZVault(offset=0)** (weak fix), **PASS on OZVault(offset=3)**.

## Quantitative proof — deterministic repro (independent of fuzzer/shrinker)
`test/DonationAttack.repro.t.sol`: attacker deposit(1 wei) → donate(1e21) → victim deposit(1e21)
→ attacker redeem all. These are authoritative per-config numbers. (The fuzz ghost
`maxProfitSeen` is seed-dependent — on a "lucky" seed a non-failing campaign showed 0, i.e. it
did not stumble onto the attack; so the measure is the deterministic scenario, not the fuzz
maximum.)

| Target | Attacker profit (assets) | Victim loss (assets) | Interpretation |
|--------|--------------------------|----------------------|----------------|
| **NaiveVault** | **+1e21** | 1e21 (**100%**) | theft: the victim's whole deposit went to the attacker |
| **OZVault(offset=0)** | **−3.33e20** | 3.33e20 (**33%**) | attacker at a loss, but victim loses 33% (stuck in virtual shares) — destructive |
| **OZVault(offset=3)** | **−4.99e20** | 2.5e17 (**0.025%**) | attacker at a loss, victim loss is dust; protection works |

Note: on offset=3 the ~0.025% victim loss is NOT theft (the attacker is at a loss) but the cost
of protection (it goes to virtual shares). I2 correctly PASS.

## Invariant fuzzing (256/64), SLACK=256
| Invariant | Role | Naive | OZ(offset=0) | OZ(offset=3) |
|-----------|------|-------|--------------|--------------|
| I2 attacker-no-profit | D (gate) | **FAIL** | **FAIL** (weak fix) | **PASS** |
| I3 solvency | C | PASS | PASS | PASS |
| I5 maxWithdraw honored | C | PASS | PASS | PASS |
| I6 preview-rounding | C | PASS | PASS | PASS |
| I7 round-trip | D₂ (2nd donation detector) | FAIL (donation-exposure) | PASS | PASS |
| I1 round-to-zero | P (Naive-only) | FAIL | — | — |
| I4 price-jump | P (Naive-only) | FAIL | — | — |

Check: **offset=3 I2 PASS at SLACK=256** (theory held, no escalation needed).

## Finding: offset=0 is a weak fix
I2 fuzzing on offset=0 fails (the attacker extracts profit > SLACK on complex sequences);
deterministically the victim loses 33% even without attacker profit. offset=3 removes both.
**Recommendation: offset ≥ 3** (OZ/Euler). Details — catalog §"Finding: offset=0 weak fix".

## Path to the result (the two-target control caught 2 method errors)
1. **Strict `profit ≤ 0` masked the attack** (failed on both by 1–2 wei: rounding dust). →
   SLACK (reformulation §4).
2. **inAssets/outAssets accounting was leaky** (phantoms from roundTrip/mint; on OZ the "profit"
   came out larger than naive). → rewritten to **CONSERVATION**:
   `profit = token.balanceOf(attacker) + previewRedeem(shares) − fundedAttacker`.
3. **SLACK tightened from 64000 to the proven 4·depth=256** — naive and offset=0 still fail,
   offset=3 holds.

## Catalog validation on known bugs — baseline 256/64, SLACK=256
Goal: show that EACH invariant catches its own bug class and stays silent on a correct contract
(OZ offset=3). The shared Handler/InvariantBase is reused (nothing in I* weakened); vulnerable
targets are purpose-built toys (`src/Bug*Vault.sol`).

**Invariant-fuzzing verdicts by target** (✗ = FAIL/caught, ✓ = PASS/silent, — = not asserted):

| Target \ Invariant | I1 | I2 (gate) | I3 | I4 | I5 | I6* | I7 |
|--------------------|----|-----------|----|----|----|----|----|
| NaiveVault (no protection) | ✗ | **✗** | ✓ | ✗ | ✓ | ✓ | ✗ |
| OZVault(offset=0) weak fix | — | **✗** | ✓ | — | ✓ | ✓ | ✓ |
| **OZVault(offset=3)** correct | — | **✓** | ✓ | — | ✓ | ✓ | ✓ |
| BugRoundingVault (rounding-dir) | — | ✗ | ✗ | — | ✓ | **✗** | ✗ |
| BugSolvencyVault (over-issuance) | — | ✓ | **✗** | — | ✗ | ✓ | ✓ |
| BugMaxWithdrawVault (max* desync) | — | ✗ | ✓ | — | **✗** | ✓ | ✗ |
| BugMinDepositVault (protection theater) | — | **✗** | ✓ | — | ✓ | ✓ | ✗ |
| BugDeadSharesVault (sound dead-shares) | — | **✓** | ✓ | — | ✓ | ✓ | ✗ |

\* I6 on BugRoundingVault is caught by the DIRECTION probe
`invariant_I6dir_previewRoundTripNoProfit` (the shared I6 checks preview-vs-execution honesty,
not rounding direction). Bold marks each target's intended invariant.

**Deterministic repros** (`test/ValidationRepros.repro.t.sol`, 10/10 PASS — fuzzer-independent):

| Bug class | Vulnerable target | Control |
|-----------|-------------------|---------|
| BUG1 rounding-direction (I6) | BugRounding: `deposit(1000)→redeem` = **1001 > 1000** | OZ(3): 999 ≤ 1000 |
| BUG2 over-issuance (I3) | BugSolvency: sum redeemable **1001 > 1000** totalAssets | Naive: 1000 = 1000 |
| BUG3 max* DoS (I5) | BugMaxWithdraw: `withdraw(maxWithdraw=2e21)` at cap=1e21 **reverts** | Naive: passes |
| BUG5 protection theater (I2) | BugMinDeposit: donation profit **+1e6** (> SLACK) | OZ(3): −1e18 |
| BUG4 dead-shares (I2, SOUND) | BugDeadShares: profit **−9.99e20** (attacker at a loss) | Naive contrast: **+1e21** |

### Finding 1: fixed dead-shares is a SOUND protection, not a weak fix
I2 **PASS** on `BugDeadSharesVault`: fixed dead shares `m=1e3` provably prevent single-victim
donation inflation — `profit = (V·D − m·(D+B))/(D+m) ≤ 0` for `m ≥ 1` (derivation in catalog
§"Catalog validation … Finding 1"). Repro: the same attack gives **−9.99e20** on dead-shares vs
**+1e21** on the bare NaiveVault → it protects precisely via dead shares. So in the matrix
dead-shares(1e3) is the SECOND I2 control (a sound protection ≠ OZ virtual-shares), not a buggy
target. The I2 gate is confirmed as a class-catcher: FAIL on 2 different vulnerable targets
(Naive donation + BugMinDeposit theater), PASS on 2 different correct ones (OZ offset=3 +
dead-shares).

### Finding 2: I7 is donation-sensitive, not a pure per-bug discriminator (refinement)
I7 fails across the whole donation family (Naive, BugRounding, BugMaxWithdraw, BugMinDeposit;
on BugDeadShares via the first depositor absorbing the donation in round-trip). This is
consistent with the earlier table (Naive I7 = FAIL) but diverges from the original catalog
wording ("I7 holds on both") — I7 is better treated as a SECOND donation-class detector, not a
control. The only control where I7 is silent is **OZ(offset=3)**. The shared
Handler/InvariantBase was not changed.

## Deeper validation: ≥3 mechanisms per invariant — seed 0x4136, 256/64
Goal: reach ~3 DIFFERENT mechanisms per I1–I7. Zero-false-positive criterion: the universal
correct contract = ONLY `OZVault(offset=3)` holds ALL I1–I7 (checked on seeds
pinned/0x1111/0x9999). A bug target MAY drop several invariants (bonus detection, not a false
positive); the intended one is **bold**. `BugDeadShares` is the sound I2 control (its I7 FAIL is
correct per Finding 2). `NaiveVault` → virtual (refactor without behavior change); +
`invariant_I5b_maxRedeemHonored`.

| Target \ Inv. | I2 | I3 | I5 | I5b | I6 | I7 | Intended / mechanism |
|---------------|----|----|----|-----|----|----|----------------------|
| **OZVault(offset=3)** (universal correct) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — (0 false positives) |
| NaiveVault | **✗** | ✓ | ✓ | ✓ | ✓ | ✗ | **I2** gate + probes I1/I4 + I7 |
| BugMinDepositVault | **✗** | ✓ | ✓ | ✓ | ✓ | ✗ | **I2** (protection theater) |
| OZVault(offset=0) | **✗** | ✓ | ✓ | ✓ | ✓ | ✓ | **I2** (weak fix) |
| BugSolvencyVault | ✓ | **✗** | ✗ | ✗ | ✓ | ✓ | **I3** (deposit +1) |
| BugSolvencyMintVault | ✓ | **✗** | ✗ | ✗ | ✓ | ✓ | **I3** (mint +1) |
| BugSolvencyBurnVault | ✓ | **✗** | ✗ | ✗ | ✓ | ✓ | **I3** (burn −1, phantom) |
| BugMaxWithdrawVault | ✗ | ✓ | **✗** | ✗ | ✓ | ✗ | **I5** (withdraw cap) |
| BugMaxRedeemLiesVault | ✗ | ✓ | ✓ | **✗** | ✓ | ✗ | **I5b** (maxRedeem lies) |
| BugRedeemCapVault | ✗ | ✓ | ✓ | **✗** | ✓ | ✗ | **I5b** (redeem cap) |
| BugRoundingVault | ✗ | ✗ | ✓ | ✓ | **✗** | ✗ | **I6** (all the math) |
| BugPreviewDepositLiesVault | ✗ | ✓ | ✓ | ✓ | **✗** | ✗ | **I6** (quote > actual in) |
| BugPreviewRedeemLiesVault | ✗ | ✗ | ✓ | ✓ | **✗** | ✗ | **I6** (quote > actual out) |
| BugDeadSharesVault (sound I2 control) | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | I2 HOLD (sound); I7 per Finding 2 |

Total DIFFERENT mechanisms per invariant: **I2=3, I3=3, I5=3** (withdraw + redeem branches),
**I6=3**; I1/I4 — probes (1 root: no offset); I7 — donation-class detector (broad). ✗ on the
non-intended cells of bug targets is bonus detection (allowed by the criterion).

### Deterministic repros (`test/ValidationReprosExtra.repro.t.sol`, 12/12 PASS)
| Inv. | Target | Number (vulnerable / control OZ3·Naive) |
|------|--------|------------------------------------------|
| I6 | BugPreviewDepositLies | previewDeposit 667 > actual shares 666 / OZ3: quote ≤ actual |
| I6 | BugPreviewRedeemLies | previewRedeem 1010 > actual payout 1000 / OZ3: ≤ |
| I5b | BugMaxRedeemLies | maxRedeem 1e18+1000 ≫ balance 1000 → redeem reverts / OZ3: ok |
| I5b | BugRedeemCap | maxRedeem 2e21 > cap 1e21 → redeem reverts / OZ3: ok |
| I3 | BugSolvencyMint | redeemable 1001 > totalAssets 1000 / Naive: ≤ |
| I3 | BugSolvencyBurn | redeemable 601 > totalAssets 600 / Naive: ≤ |

### Additional findings
- **SLACK (price-aware rejected):** a price-aware SLACK (`4·depth·P`) was considered and
  REJECTED — empirically it KILLS the I2 gate (under donation inflation P~(D+V),
  profit=V < 4·depth·P ⇒ I2 PASS on Naive/BugMinDeposit). The absolute SLACK=256 is kept (gate
  alive); "zero false positives" is reformulated per target (a false positive = only the
  OZ3/sound role). The earlier matrix was seed-dependent — now refined. The ghost `maxSharePrice`
  is kept for the number P. A valuable methodological result (price-aware looks more honest but
  is blind to donation).
- **I1/I4 — probes of a single root** (no virtual offset): a "2nd mechanism" would be the same
  root on another naive contract, not a new one. Suppressed only by offset≥3 (dead-shares does
  NOT suppress it — dead-shares protects I2 only). Recorded as a probe, not stretched to 3.
- **I7 — class detector** for donation-exposure (not a set of mechanisms): fails across the
  family, silent only on OZ(3).

## Environment
All builds and fuzzing run inside a sandboxed Docker container (rootless, resource-limited); the
test is offline once dependencies are fetched. The fuzzer seed is pinned in `foundry.toml`
(`[fuzz] seed=0x4136`) for reproducible numbers; correctness of OZ(3) was checked on 2–3 seeds.

## Verification commands
Standard Foundry project. From `poc-erc4626/`, after installing dependencies:

```bash
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts@v5.1.0

forge test --mc DonationAttackRepro -vv     # deterministic per-config numbers (core of the proof)
forge test                                   # full campaign: naive/offset0 FAIL I2, offset3 PASS
forge test --mc ValidationRepros -vv        # 10 deterministic validation repros (10/10 PASS)
forge test --mc ValidationReprosExtra -vv   # 12 deterministic repros of the extra targets (12/12 PASS)
forge clean && forge test --mc Invariant    # full matrix (≥3 mech./inv.); OZ(3) holds all, I2 gate FAIL on Naive
```

Builds and fuzzing of third-party contracts should run in a sandboxed container; the contracts
here are small purpose-built ones.
