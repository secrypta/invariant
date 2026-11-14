// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ICToken} from "../src/ICToken.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {GenComptrollerStub} from "../src/GenComptrollerStub.sol";
import {GenIRMStub} from "../src/GenIRMStub.sol";
import {Handler} from "./Handler.sol";

/// @title InvariantBase - CROSS-TARGET invariants of the cToken catalog (catalog/ctoken.md).
/// @notice The target provides the subclass via _deployCToken(). Here are the invariants identical for BOTH targets:
///   CT1 (discriminator-gate - FAIL on Naive / HOLD on Safe = the fix criterion), CT3/CT4 (controls - HOLD on both),
///   CT5 (D₂ donation detector - FAIL on Naive / HOLD on Safe; confirmed over 3 seeds: overshoot ≫ SLACK on Naive,
///   ≤ SLACK on Safe). The CT2 probe (round-to-zero) is Naive-only, in NaiveCToken.invariant.t.sol (like I1/I4 in erc4626).
/// The CT1 gate is formulated IDENTICALLY to erc4626 I2: wealth from public getters, SLACK = 4·depth - one family, one formula.
abstract contract InvariantBase is Test {
    MockERC20 internal token;
    ICToken internal cToken;
    Handler internal handler;

    address internal constant ATTACKER = address(0xA11CE);
    address internal constant VICTIM1 = address(0xB0B);
    address internal constant VICTIM2 = address(0xCA201);

    // SLACK = 4·depth - a proven floor on rounding noise (catalog/erc4626.md §"Why SLACK = 4·depth", carried over unchanged).
    uint256 internal constant DEPTH = 64;
    uint256 internal constant SLACK = 4 * DEPTH; // = 256 at depth=64

    function _deployCToken(MockERC20, GenComptrollerStub, GenIRMStub) internal virtual returns (ICToken);

    function setUp() public {
        token = new MockERC20();
        GenComptrollerStub comptroller = new GenComptrollerStub();
        GenIRMStub irm = new GenIRMStub();
        cToken = _deployCToken(token, comptroller, irm);

        address[] memory actors = new address[](3);
        actors[0] = ATTACKER;
        actors[1] = VICTIM1;
        actors[2] = VICTIM2;
        handler = new Handler(cToken, token, actors);

        // Fuzz selectors: ACTIONS only; seedFirstMint is excluded (a one-time precondition, not repeatable).
        bytes4[] memory sel = new bytes4[](5);
        sel[0] = Handler.mintAct.selector;
        sel[1] = Handler.donateAct.selector;
        sel[2] = Handler.redeemAct.selector;
        sel[3] = Handler.redeemAllAct.selector;
        sel[4] = Handler.roundTrip.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: sel}));
        targetContract(address(handler));

        // Donation-attack precondition: a tiny first mint by the attacker into an empty market.
        handler.seedFirstMint(1);
    }

    // ===== CT1 - gate (FAIL on Naive / HOLD on Safe) =====
    /// wealth = underlying.balanceOf(atk) + balanceOf_shares(atk)·exchangeRateStored()/1e18; profit = wealth − funded ≤ SLACK.
    /// From PUBLIC getters (NOT internalCash). The proof is quantitative - handler.maxProfitSeen().
    function invariant_CT1_attackerNoProfit() public view {
        address atk = handler.attacker();
        uint256 wealth = token.balanceOf(atk) + cToken.balanceOf(atk) * cToken.exchangeRateStored() / 1e18;
        assertLe(wealth, handler.fundedAttacker() + SLACK, "CT1: attacker profit > SLACK");
    }

    // ===== CT3 - conservation/solvency (control, HOLD on both) =====
    /// Σ_h balanceOf_shares(h)·exchangeRateStored()/1e18 ≤ getCash() + totalBorrows − totalReserves.
    function invariant_CT3_solvency() public view {
        uint256 n = handler.holdersLength();
        uint256 rate = cToken.exchangeRateStored();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            sum += cToken.balanceOf(handler.holders(i)) * rate / 1e18;
        }
        assertLe(sum, cToken.getCash() + cToken.totalBorrows() - cToken.totalReserves(), "CT3: sum redeemable > available assets");
    }

    // ===== CT4 - redeem is honest BY AMOUNT (control, fund-safety, HOLD on both) =====
    /// A shift from liveness ("redeem does not revert" - too strong for a real cToken, which legitimately
    /// reverts on insufficient cash) to fund-safety: redeem does NOT silently short-change. redeemViolation is set
    /// ONLY on a SUCCESSFUL redeem with an unfair amount / broken accounting (see Handler._redeemHonored).
    /// A revert / error code = a safe refusal → HOLD. Catches a real redeem bug, not a false positive on a real cToken.
    function invariant_CT4_redeemHonored() public view {
        assertFalse(handler.redeemViolation(), "CT4: redeem paid an unfair amount / broke share accounting");
    }

    // ===== CT5 - round-trip with no profit (D₂ donation detector: FAIL on Naive / HOLD on Safe) =====
    /// Catches extraction via donation-exposure: in a donation-inflated market the round-tripper gets back > amt.
    /// Confirmed over 3 seeds: overshoot ≫ SLACK on Naive, ≤ SLACK on Safe. The fix criterion remains CT1.
    function invariant_CT5_noRoundTripProfit() public view {
        assertLe(handler.maxRoundTripOvershoot(), SLACK, "CT5: round-trip overshoot > SLACK");
    }
}
