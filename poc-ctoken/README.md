# poc-ctoken - cToken invariant catalog harness (Venus donation / exchange-rate inflation)

A Foundry invariant-fuzzing implementation of [`catalog/ctoken.md`](../catalog/ctoken.md), run against a **real,
verbatim third-party target**: the Venus Protocol money-market (`VBep20`, a Compound-V2 fork). This is the project's
second open end-to-end example (first is [`poc-erc4626`](../poc-erc4626)).

**The invariant harness in [`test/`](test) and the stubs in [`src/`](src) were PRODUCED BY the generator**
(`invgen scan`: detect → generate), not hand-written. The same generated harness is run against two verbatim Venus
commits:

- **VULN** - `vendor/vuln/` @ commit `9c6467db` (develop, before PR #664).
- **FIX** - `vendor/fix/` @ PR #664 head (VPD-808 "Add internal cash to prevent donation attack").

Gate discriminator: **CT1** (attacker-no-profit) - **FAIL** on VULN, **PASS** on FIX. The donation attack: the first
minter of an empty market inflates the exchange rate with a direct `underlying` transfer so later minters round to
zero shares, letting the attacker capture their deposits.

## Tier: TIER-1 (full-blind)
Both sides are genuine, verbatim third-party source at pinned historical commits - the real vuln/fix pair, with no
reconstruction on our part. `detect` identifies the type as `ctoken` **blind** (no hint) on both sides. Licenses
(BSD-3-Clause, Compound/Venus author headers) and SPDX headers are preserved byte-for-byte; see
[`PROVENANCE.md`](PROVENANCE.md).

## Structure
- `test/VBep20.invariant.t.sol`, `test/InvariantBase.sol`, `test/Handler.sol` - **generator-produced** harness,
  verbatim (CT1 gate + CT3/CT4/CT5 controls, Handler/Actors pattern). Answer-agnostic: identical for any cToken
  target; the target is pulled in only via the `target/` remapping.
- `src/{ICToken,MockERC20,GenComptrollerStub,GenIRMStub}.sol` - generator-produced interface + permissive ABI stubs.
- `vendor/vuln/`, `vendor/fix/` - verbatim Venus target trees (`vendor/` + `vendor_ext/`), differing only in
  `VBep20.sol` + `VTokenInterfaces.sol` (the donation fix). Each is the exact dependency set the harness compiles.
- `vendor/ext/forge-std/` - vendored forge-std (MIT). OpenZeppelin (MIT) + Venus governance/oracle/solidity-utilities
  are vendored under each side's `vendor_ext/`.

The two sides never coexist in one compilation: the `target/` (and `venus/`, `@openzeppelin/`, `@venusprotocol/`)
remappings are set per Foundry profile - `default` → `vendor/vuln/`, `fix` → `vendor/fix/` - so only the active
side is compiled.

## Dependencies (self-contained)
All Solidity sources - the Venus targets, OpenZeppelin, and forge-std - are **vendored**; the build fetches no
source. The only external artifact is the `solc 0.8.25` compiler, which the Foundry toolchain downloads on first
use (it can be pre-provisioned in the image for a fully air-gapped run).

## How to run (Docker; builds/fuzzing run only in a sandboxed container)
```bash
# VULN side (default profile) - expect CT1 to FAIL (bug re-opened):
docker run --rm --entrypoint bash -v "$PWD":/work -w /work invgen-tools:1 \
  -lc "forge test --match-contract VBep20Invariant -vv"

# FIX side (fix profile) - expect everything to hold (correct-silence):
docker run --rm --entrypoint bash -e FOUNDRY_PROFILE=fix -v "$PWD":/work -w /work invgen-tools:1 \
  -lc "forge test --match-contract VBep20Invariant -vv"
```

## Expected result
| Invariant | Role | VULN @9c6467db | FIX @PR#664 |
|-----------|------|----------------|-------------|
| **CT1 attacker-no-profit** | **discriminator (gate)** | **FAIL** | **PASS** |
| CT3 solvency | control | PASS | PASS |
| CT4 redeem-honored | control | PASS | PASS |
| CT5 round-trip overshoot | donation-class detector | FAIL | PASS |

The gate is CT1. A VULN run fails it (attacker profit ≫ SLACK) and the fuzzer records the call sequence; a FIX run
holds all four, non-vacuously (the gate-moving `mintAct` is reached). Numbers are in [`RESULT.md`](RESULT.md).
If a cross-target invariant fails on the FIX side - fix the formulation, not the contract.
