# invariant-gen — ERC-4626 invariant harness

A catalog of economic/safety invariants for ERC-4626 tokenized vaults, with a Foundry
fuzzing harness that **re-discovers a known class of vault bug on a vulnerable contract and
stays silent on a correct one** — no false positives. An invariant is validated by a function
body that fuzzing can break, not by prose.

This repository is the ERC-4626 slice: an invariant specification (`catalog/erc4626.md`) and a
self-contained Foundry project (`poc-erc4626/`) that exercises every invariant against
purpose-built contracts.

## Why this exists

**What this is.** A worked, reproducible example of invariant-based security testing for
ERC-4626 vaults: a catalog of economic/safety invariants, a Foundry fuzzing harness, and
purpose-built toy vaults (both vulnerable and correct) that prove the harness works.

**What it demonstrates.** The harness re-discovers the classic donation/inflation attack on a
vulnerable vault and stays silent on a correct one — no false positives. A deterministic repro
shows an attacker taking 100% of a victim's deposit on a naive vault, versus dust (~0.025%)
loss with the attacker at a loss on an OpenZeppelin vault with offset >= 3. It also shows that
offset = 0 is a weak fix (the victim still loses 33%).

**Principle.** An invariant is validated by a function body that fuzzing can break — not by prose.

**Scope & honesty.** This covers one contract type (ERC-4626) as a reference. It is meant to be
useful as a template you can point at your own vault, and as a teaching example of how to write
invariants, a Handler, and a fuzzing campaign in Foundry. MIT-licensed; runs in a sandboxed
Docker container with a pinned seed for reproducibility.

## The idea

Most fuzzing setups run the fuzzer but leave the hard part to you: **deciding what must always
be true**. Here the invariants come first, as a catalog, and each one is backed by a concrete
assertion plus a contract that is supposed to break it. The gate invariant is **I2 —
attacker-no-profit** (the first-depositor / donation inflation attack): an attacker deposits
1 wei, donates directly to the vault to inflate the share price, and the next depositor rounds
down — the attacker captures the difference. The reference fix is OpenZeppelin's virtual-shares
offset.

The verdict is quantitative. For I2, a deterministic repro (`test/DonationAttack.repro.t.sol`,
independent of the fuzzer) gives per-configuration numbers:

| Target | Attacker profit (assets) | Victim loss | Verdict |
|--------|--------------------------|-------------|---------|
| `NaiveVault` (no offset) | **+1e21** | 1e21 (100%) | theft — the victim's whole deposit |
| `OZVault` offset=0 | −3.33e20 | 3.33e20 (33%) | attacker at a loss, but victim still loses 33% |
| `OZVault` offset=3 | −4.99e20 | 2.5e17 (0.025%) | protection holds — dust, attacker at a loss |

The fuzzing verdict line (SLACK = 4·depth = 256 wei, a proven rounding-noise ceiling, not a
theft threshold): I2 **FAIL** on `NaiveVault` and `OZVault(offset=0)`, **PASS** on
`OZVault(offset=3)`. The offset=0 default is a *weak* fix — consistent with OpenZeppelin's own
guidance that the default makes the attack unprofitable, not impossible; a non-zero offset
(≥ 3, as OpenZeppelin/Euler use) is required for the gate to hold.

## Invariants and the contracts that break them

Each invariant is exercised by several distinct bug mechanisms, so a gate catches a *class* of
bugs rather than a single implementation. The only universally correct target — holding every
invariant I1–I7 — is `OZVault(offset=3)`; it is the false-positive control.

| Invariant | What it asserts | Vulnerable contracts that it catches |
|-----------|-----------------|--------------------------------------|
| **I2** attacker-no-profit (gate) | donation/inflation cannot profit an attacker | `NaiveVault`, `BugMinDepositVault`, `OZVault(offset=0)` |
| I3 solvency | sum of redeemable ≤ total assets (no over-issuance) | `BugSolvencyVault`, `BugSolvencyMintVault`, `BugSolvencyBurnVault` |
| I5 maxWithdraw honored | a withdraw up to `maxWithdraw` never reverts | `BugMaxWithdrawVault` |
| I5b maxRedeem honored | a redeem up to `maxRedeem` never reverts | `BugMaxRedeemLiesVault`, `BugRedeemCapVault` |
| I6 preview honesty | `preview*` never quotes better than execution | `BugRoundingVault`, `BugPreviewDepositLiesVault`, `BugPreviewRedeemLiesVault` |
| I7 round-trip (2nd donation detector) | deposit→redeem cannot gain | the whole donation family; silent only on `OZVault(offset=3)` |
| I1 round-to-zero / I4 price-jump | mechanism probes (asserted on `NaiveVault` only) | `NaiveVault` |

`BugDeadSharesVault` is a **second I2 control**: fixed dead shares (`m = 1e3`) provably prevent
single-victim donation inflation (`profit = (V·D − m·(D+B))/(D+m) ≤ 0` for `m ≥ 1`), so I2
holds — a sound fix that is *not* OpenZeppelin's virtual shares. The same donation that nets
+1e21 on bare `NaiveVault` nets −9.99e20 here.

## Quick start

The project is a standard Foundry project. From `poc-erc4626/`, install dependencies and run:

```bash
cd poc-erc4626
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts@v5.1.0

forge test --mc DonationAttackRepro -vv    # the deterministic per-config numbers above
forge test                                  # full invariant campaign: I2 FAIL on Naive/offset=0, PASS on offset=3
forge test --mc ValidationRepros -vv        # deterministic repros for the bug-vs-control matrix
```

Builds and fuzzing of third-party contracts should run in a sandboxed container; the contracts
here are small purpose-built ones. The fuzzer seed is pinned in `foundry.toml` for reproducible
numbers.

## Honest scope

This is a demonstration on **purpose-built toy contracts**, not a claim about real deployments:

- The `Bug*Vault` contracts are deliberate *reconstructions* of known vault bug classes
  (donation inflation, over-issuance, lying `preview`/`max*`, rounding direction), written to
  make each invariant fire. They are not copies of any production contract.
- `OZVault` wraps OpenZeppelin's own ERC-4626 implementation, so "the harness stays silent on
  the fix" is partly true *by construction* — the fixed side literally is the upstream fix. The
  meaningful signal is that the same assertions fire on the vulnerable reconstructions and hold
  only on a genuinely correct configuration (`offset=3` / sound dead shares).
- The invariants are asserted on ERC-4626 vaults only. Other protocol types are out of scope
  for this slice.

## Layout

- `catalog/erc4626.md` — the invariant specification (roles: gate / control / detector,
  tolerance derivations, the offset=0 weak-fix finding).
- `poc-erc4626/src/` — `MockERC20`, `IVault`, `NaiveVault`, `OZVault`, and the `Bug*Vault`
  reconstructions.
- `poc-erc4626/test/` — `Handler` + `InvariantBase` (invariants I1–I7), per-target invariant
  bindings, and deterministic repro tests.
- `poc-erc4626/RESULT.md` — the recorded fuzzing run, the matrix, and the findings.

## License

MIT — see [LICENSE](LICENSE). Dependency attribution (forge-std, OpenZeppelin) is in
[NOTICE](NOTICE).

Built and maintained by [secrypta](https://secrypta.com).
