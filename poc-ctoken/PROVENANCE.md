# Provenance - Case B (Venus Protocol, donation / exchange-rate inflation)

Source repo: https://github.com/VenusProtocol/venus-protocol  - License: BSD-3-Clause (preserved in SPDX headers).
- vuln/vendor  = verbatim @ commit 9c6467db09242330da2d3079200e14ae7e659adf (develop before PR #664)
- fix/vendor   = verbatim @ commit e1b9231f3f5191be91eb70668cb4cd91e00abf0c (head of PR #664, VPD-808)
PR #664 "[VPD-808] Add internal cash to prevent donation attack"; merge 7c95843dc628535bfd0cf628c53bf7f7a2162932.
External interfaces/constants under vendor_ext/ (OZ MIT; @venusprotocol governance/oracle/solidity-utilities BSD-3-Clause)
are ABI/constants only, not behavior. Stubs (Step 2) live under src/ and do NOT touch the exchange-rate/donation path.

License: full BSD-3-Clause text with Venus Labs copyright in {vuln,fix}/vendor/LICENSE (fetched from the pinned commit).
Derivation: Venus is a Compound-V2 fork; the Exponential/VToken lineage is marked `@author Compound` in the original
file headers (BSD-3-Clause), which are preserved verbatim. Original SPDX + author headers of every vendored .sol are
kept as-is (no MIT header of ours was placed over third-party code).
