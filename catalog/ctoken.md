# Invariant catalog: cToken (Compound-V2 money-market share)

Each invariant is stated as an **inequality over state**, not as prose - it is checked by the
body of an `invariant_*()` / Handler action hook, not by a comment.

The `ctoken` type covers Compound-V2 forks (cToken / vToken). Economically these are the same
donation / exchange-rate-inflation class as ERC-4626 vaults, but the ABI differs: `mint(uint256)`
returns an error code, plus `exchangeRateStored`, `redeem` / `redeemUnderlying`, and `comptroller`.
The goal is that the `detect → generate → run` pipeline lands on a real Compound-V2-fork VToken
**blind** and returns the correct verdict from the invariant body.

The gate belongs to the share-accounting / attacker-no-profit family, not the lending
health/solvency family. The fix mechanic lives in `getCashPrior`: balance → internal cash counter
(as in Venus PR #664 / VPD-808).

## Two-target rule (false-positive control)
Every invariant runs against TWO purpose-built toy cTokens (our own contracts, not taken from any
third-party repo; a real VToken is used only for the end-to-end validation step):

- **(a) `NaiveCToken`** - a minimal Compound-V2-style money-market. Key math:
  - `exchangeRateStored() = totalSupply()==0 ? initialRate : (getCashPrior() + totalBorrows − totalReserves) * 1e18 / totalSupply()`
  - `mint(uint)`: `mintTokens = actualMintAmount * 1e18 / exchangeRateStored()` (round-down); `mint` returns a code (0 = OK).
  - `getCashPrior() = underlying.balanceOf(address(this))` ← the weakness: a direct `transfer`
    (donation) grows cash → grows `exchangeRate` without minting shares → the next victim `mint`
    rounds down (round-to-zero) and value leaks.
  - `redeem(uint)` / `redeemUnderlying(uint)` - per `exchangeRate`, rounding down on the depositor's shares.
- **(b) `SafeCToken`** - the same contract byte-for-byte except `getCashPrior()`:
  - `getCashPrior() = internalCash` - an internal counter, `+=` in `doTransferIn` / `−=` in
    `doTransferOut`; a raw `transfer` is not counted. The donation is ignored by `exchangeRate`.
    **Reference fix: exactly Venus #664.**
  - ⚠️ The ONLY difference between the bodies of `NaiveCToken` ↔ `SafeCToken` is the `getCashPrior`
    line plus the `internalCash` tracking. The body diff is the proof of answer-agnosticism (one
    generate command for both; the only difference is the target body).

**Role semantics** (as in erc4626/amm/…):
- `D` (discriminator-gate) - MUST fail on `NaiveCToken` and hold on `SafeCToken`. This is the fix criterion.
- `C` (control / false-positive guard) - MUST hold on BOTH; a failure means a real accounting bug
  or a bad formulation (fix the formulation, not the contract).
- `D₂` (second donation-class detector) - fails on donation-vulnerable targets (including the bare
  `NaiveCToken`) and is silent on the fix. Not a control, but not the sole gate either - CT1 remains the criterion.
- `P` (mechanism probe) - expected to fire on `NaiveCToken`, but MAY also fire on `SafeCToken`,
  and that is NOT a bug in the fix (the counter removes the donation PROFIT, not the round-to-zero
  itself). On the safe target probes are not asserted; their values are logged as ghost.

## Summary table
| ID | Role | Invariant (inequality) | Catches | Naive | Safe |
|----|------|------------------------|---------|-------|------|
| **CT1** | **D (gate)** | for the attacker: `wealth ≤ fundedAttacker + SLACK` (profit ≤ 0), where `wealth = underlying.balanceOf(atk) + balanceOf_shares(atk)·exchangeRateStored()/1e18` | donation / exchange-rate inflation profit | **FAIL** | **PASS** |
| CT2 | P | legit `mint(amt)` with `amt ≥ DUST` and a success code → `balanceOf_shares > 0` | first-minter round-to-zero | FAIL | fires¹ |
| CT3 | C | `Σ_h balanceOf_shares(h)·exchangeRateStored()/1e18 ≤ getCash() + totalBorrows − totalReserves` | over-issuance / conservation hole | PASS | PASS |
| CT4 | C | on success, `redeem` pays a fair amount (shares·exchangeRate within a rate±truncation band) and burns shares/supply exactly; a revert / error code = deviation (HOLD) | silent short-change / broken redeem accounting | PASS | PASS |
| CT5 | **D₂ (donation)** | round-trip `mint(amt)`→`redeem` by one actor in an inflated market: overshoot `back − amt ≤ SLACK` | value extraction via donation-exposure | **FAIL** | **PASS** |

¹ CT2 may fire on Safe as expected (the internal counter removes the donation PROFIT, not the
round-to-zero at an extreme first mint) - this is NOT a bug in the fix; on Safe it is not asserted,
the value goes to a ghost. The gate is row **CT1**.

In total **5 invariants**: 1 discriminator-gate (CT1), 1 second donation-class detector (CT5),
2 controls (CT3/CT4), 1 probe (CT2).

---

## CT1 - attacker gets no net profit (gate) `[D - the sole discriminator]`
**Statement (accounting via conservation, from public getters).** For a designated `attacker`, at
any point: `wealth(attacker) ≤ fundedAttacker + SLACK`, where
`wealth = underlying.balanceOf(attacker) + balanceOf_shares(attacker)·exchangeRateStored()/1e18`,
and `fundedAttacker` is EVERYTHING credited to the attacker (each underlying mint into their hands
plus any raw donation). `profit = wealth − fundedAttacker ≤ SLACK`.

**Why it matters.** `exchangeRate = (cash + totalBorrows − totalReserves)/totalSupply`,
`cash = getCashPrior()`. On Naive `getCashPrior = underlying.balanceOf(this)`, so a raw donation
inflates the rate → the rounding in `mintFresh` steals from the next depositor; the attacker takes
the leaked value out via `redeem`. The invariant catches this as an economic fact, not as the
"absence of a guard".

**How to encode (Foundry).**
- Actors: `actors[0] = attacker`, the rest are victims (the fuzzer drives their mints, creating the attack condition).
- Ghost `uint256 fundedAttacker` - everything credited to the attacker: in `_fund` (underlying mint before a mint action) and in `donateAct`.
- `invariant_CT1_attackerNoProfit()`:
  `uint256 wealth = underlying.balanceOf(attacker) + target.balanceOf(attacker) * target.exchangeRateStored() / 1e18;`
  `assertLe(wealth, handler.fundedAttacker() + SLACK);`
- Ghost `int256 maxProfitSeen` for the report (the fuzz max is seed-dependent → the reported NUMBER comes from a deterministic repro).

**Critical (answer-agnostic).** `wealth` is measured ONLY from the public getters
`exchangeRateStored()` / `balanceOf`, NEVER from `internalCash` / `getCashPrior` (the buggy field) -
otherwise the gate would "peek" at the answer. SLACK is mandatory (rounding dust masks the attack;
see §SLACK). The donation MUST be included in `fundedAttacker`, otherwise the gate would falsely
catch its own donation.

**Expectation.** `NaiveCToken`: (mint 1 → donate big → victim mint → attacker redeem) gives
`profit ≫ SLACK` → **fails** (Foundry gives a repro). `SafeCToken`: the donation is ignored
(internalCash), `profit ≤ 0` → **holds**.

## CT2 - no round-to-zero on a meaningful mint `[P - mechanism probe]`
**Statement.** For an actor `a` and `code = mint(amt)`: if `amt ≥ DUST` and `code == 0` (success),
then the increase in `balanceOf_shares(a) > 0`. This is the core of the first-minter attack (after
a donation the rate is inflated → `amt·1e18/rate = 0`). Ghost flag in the action:
`if (amt >= DUST && code == 0 && mintedShares == 0) roundToZeroSeen = true;`. Asserted on Naive,
logged on Safe.

## CT3 - conservation: total redeemable ≤ available assets `[C]`
`Σ_{h∈holders} balanceOf_shares(h)·exchangeRateStored()/1e18 ≤ getCash() + totalBorrows() − totalReserves()`.
Solvency: holders cannot be promised more than the market holds. Insensitive to a donation (the
market stays solvent - it is fairness that suffers) → a control, holds on both. A failure on Safe
means the formulation needs fixing (round-down / reserves).

## CT4 - redeem is honest BY AMOUNT `[C - fund-safety, not liveness]`
Redeem does not silently short-change. On success (`err == 0`): the underlying received `==` the
burned shares·`exchangeRateStored()`/1e18 (within the rate band before/after - accrual-safe; ± a
single mantissa truncation, a tolerance DERIVED from the formula, not tuned), and shares and
`totalSupply` are reduced by exactly `redeemTokens`. A REVERT OR a non-zero error code = the
protocol declined (e.g. a legitimate cash guard `getCash() < owed`,
`REDEEM_TRANSFER_OUT_NOT_POSSIBLE`) - safe behavior, NOT theft → HOLD. Everything from public
getters, answer-agnostic. Holds on both; catches a real redeem bug (silent short-change).

> Boundary (honest): an earlier "redeem does not revert" (liveness) formulation failed
> symmetrically on a real Compound-V2 fork - a cToken legitimately reverts on insufficient cash.
> Distinguishing a buggy DoS-redeem from a legitimate cash refusal from public state alone is
> impossible without answer-awareness → the liveness aspect is NOT taken into CT4 (any non-success
> is HOLD). Ground truth is the run.

## CT5 - round-trip with no profit `[D₂ - second donation-class detector]`
`mint(amt)`→`redeem(shares)` by one actor (new shares) returns `≤ amt + SLACK`. Like CT1, it
catches extraction via donation-exposure: in a donation-inflated market the round-tripper extracts
`back > amt`. FAIL on Naive, HOLD on Safe.

> Note (honest): the initial static prediction was that an atomic round-trip would NOT discriminate
> (a symmetric floor). The run refuted this - the overshoot arises from the donation-exposure of
> the round-tripper's new shares in the inflated market. Ground truth is the run, not reasoning.
> Not the sole gate: the criterion is CT1.

---

## Why SLACK = 4·depth
Carried over from `catalog/erc4626.md` §"Why SLACK = 4·depth" unchanged: rounding moves the
share price only upward, and over one other party's operation a holder receives `<` the share
price; with no yield/manipulation `< 1 wei/op ⇒ < depth wei` per run, ×4 margin.
`SLACK = 4·depth = 256` at `depth = 64`. A strict `≤ 0` would catch dust and mask the attack.
The proof of re-discovery is in the MAGNITUDE of the profit (deterministic repro:
`profit(Naive) ≫ SLACK`, `profit(Safe) ≤ 0`).

## DETECT - cToken ABI profile (answer-agnostic, NOT by name)
cToken markers (required): `mint(uint256)`, `redeem(uint256)`, `redeemUnderlying(uint256)`,
`borrow(uint256)`, `exchangeRateStored()`, `exchangeRateCurrent()`, `balanceOf(address)`,
`totalSupply()`, a `comptroller()` getter, and (cErc20 / vBep20) `underlying()`. Optional:
`accrualBlockNumber()`, `getCash()`, `totalBorrows()`, `totalReserves()`.
**Discriminator from erc4626:** a cToken `mint` is single-argument (`mint(uint256)`, returns an
error code), with NO `deposit(uint256,address)` / `mint(uint256,address)` / `convertToShares` /
`asset()`. ABI-shape-based, independent of the contract name.

## GENERATE / ENV - what the type builds around the target (all OFF the bug path)
- **cToken deploy profile:** direct deployment - the constructor sets `admin = msg.sender`, then
  `initialize(...)`. The generator declares slots `underlying/comptroller/irm/initRate/name/symbol/decimals`
  and fills them from the parameter NAMES of `initialize` in the target ABI
  (underlying → MockERC20, comptroller → stub, irm → stub, rate → 1e18, decimals → default). Where a
  fork does not map onto the slots it is an honest boundary (do not guess) - a hard error plus a note.
- **permissive Comptroller stub:** generated FROM the ABI of the interface the target imports - all
  `view`/`pure` → return 0/default, all non-view → no-op (`NO_ERROR`). A hand-written
  protocol-specific ~50-function stub is FORBIDDEN (risk of hiding/creating a bug). If the
  auto-stub-from-interface does not fit the timebox it is an HONEST BOUNDARY, recorded in the
  report - not smuggled in. The stub does NOT read/modify `exchangeRate`/`cash` (verified against the body).
- **IRM stub** zero-rate (`getBorrowRate = getSupplyRate = 0`) → `accrueInterest` is a no-op on `exchangeRate`.
- **underlying** - MockERC20 (18 decimals).
- **handler actions:** `seedFirstMint(1)` in setUp (a documented attack precondition, EXCLUDED from
  the fuzz selectors); `mintAct` (force small in an empty market); `donateAct` = a RAW
  `underlying.transfer(address(target), amt)` (without it the bug is unreachable - cToken-donation
  specific); `redeemAct`.

## Catalog validation
- **Golden step (no Docker / no real code):** our own `NaiveCToken` / `SafeCToken` + harness → CT1
  FAIL on Naive / HOLD on Safe (0 false positives on controls), 3 seeds, 256×64, `fail_on_revert=false`.
  The body diff Naive ↔ Safe is only `getCashPrior`.
- **Generator step:** `types/ctoken.py` + `templates/ctoken/`, emit regression vs golden, ABI detect.
- **Real-fork validation step:** a real Compound-V2-fork VToken, one generate command for vuln/fix →
  CT1 FAIL/HOLD from the body. solc 0.8.25.
- Honesty boundary: if the stub creates OR hides the bug, the test is INVALID. The case is public.

## Sources of the pattern / fix (public)
Compound-V2 cToken (cash-based `exchangeRate`), donation / first-depositor inflation; fix =
internal-cash tracking (`getCashPrior`: balanceOf → internalCash). Venus PR #664 (VPD-808).
