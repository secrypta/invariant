# poc-erc4626 — ERC-4626 invariant catalog harness

A Foundry invariant-fuzzing implementation of [`catalog/erc4626.md`](../catalog/erc4626.md).
Targets: the vulnerable `NaiveVault` (no offset) and the fixed `OZVault` (OpenZeppelin
virtual-shares offset), plus purpose-built `Bug*Vault` reconstructions — one per invariant class.
Gate discriminator: **I2** (attacker-no-profit) — FAIL on `NaiveVault`, PASS on
`OZVault(offset=3)`. The OZ offset protects the PROFIT of the attack, not round-to-zero/price —
so the mechanism probes I1/I4 fire on OZ too and are asserted only on the naive run.

## Status
Validated: I2 FAIL on `NaiveVault` (profit +1e21) / PASS on `OZVault` (offset=3, −5e20). Plus
catalog validation: purpose-built bug targets + 2 controls, the full I1–I7 matrix, and
deterministic repros. Numbers and findings are in [`RESULT.md`](RESULT.md). Builds and fuzzing
run inside a sandboxed Docker container.

## Structure
- `src/MockERC20.sol` — toy asset.
- `src/NaiveVault.sol` — vulnerable target (discriminator D).
- `src/OZVault.sol` — fixed target (false-positive control).
- `src/IVault.sol` — shared ERC-4626 interface for both targets.
- `src/Bug*Vault.sol` — purpose-built bug reconstructions (one per invariant class).
- `test/Handler.sol` — actions + ghost variables (Handler/Actors pattern).
- `test/InvariantBase.sol` — invariants I1–I7.
- `test/{NaiveVault,OZVault}.invariant.t.sol` — per-target bindings.
- `test/*.repro.t.sol` — deterministic repros.

## Dependencies
- `forge-std`
- `openzeppelin-contracts` **v5.1.0** (remappings → `lib/openzeppelin-contracts/contracts/`)

## How to run
```bash
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts@v5.1.0

forge test --mc NaiveVaultInvariant -vvv    # vulnerable target — expect I1/I2/I4 to fail
forge test --mc OZVaultInvariant -vvv        # fixed target — expect everything to hold
```

## Expected result
| Invariant | Role | NaiveVault | OZVault |
|-----------|------|-----------|---------|
| **I2 attacker-no-profit** | **discriminator (gate)** | **FAIL** | **PASS** |
| I3 solvency | control | PASS | PASS |
| I5 max* consistency | control | PASS | PASS |
| I6 preview-rounding | control | PASS | PASS |
| I7 round-trip | donation-class detector | FAIL | PASS |
| I1 round-to-zero | mechanism probe (Naive-only assert) | FAIL | (fires, not asserted) |
| I4 price-jump | mechanism probe (Naive-only assert) | FAIL | (fires, not asserted) |

The gate is row I2. I1/I4 are asserted only in `NaiveVaultInvariant`; on OZ they fire (the offset
protects profit, not these mechanics) and are not checked there — their values are read from ghost
flags in `RESULT.md`. On a violation Foundry gives the call sequence → save it as a deterministic
`test_repro_*()` and describe it in `RESULT.md`. If a cross-target invariant (I2/I3/I5/I6/I7) fails
on `OZVault` — fix the formulation, not the contract.
