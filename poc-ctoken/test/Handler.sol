// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ICToken} from "../src/ICToken.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @title Handler - the fuzzer "steering wheel" for the cToken (Handler/Actors pattern).
/// actors[0] is the attacker; the rest are victims. The fuzzer combines their mint/donate/redeem into the donation-attack condition.
///
/// PROFIT ACCOUNTING (CT1) - via CONSERVATION, from PUBLIC getters (NOT from internalCash - the buggy field):
///   wealth(attacker) = underlying.balanceOf(attacker) + balanceOf_shares(attacker)·exchangeRateStored()/1e18
///   profit(attacker) = wealth − fundedAttacker, where fundedAttacker is EVERYTHING credited to the attacker
///   (seed mint + each underlying mint into their hands + the raw donation). profit > 0 = value leaked from victims.
///   Measured ONLY from the public getters exchangeRateStored()/balanceOf, NEVER from internalCash (the buggy field).
contract Handler is Test {
    ICToken public cToken;
    MockERC20 public token;
    address[] public actors;
    address public attacker;

    address[] public holders;
    mapping(address => bool) internal seenHolder;

    // --- ghost ---
    uint256 public fundedAttacker;                      // CT1: total assets credited to the attacker
    int256 public maxProfitSeen = type(int256).min;     // CT1: max observed profit (for the report)
    bool public roundToZeroSeen;                        // CT2: a successful mint(amt>=DUST) yielded 0 shares
    bool public redeemViolation;                        // CT4: redeem SUCCEEDED but paid an unfair amount / broke accounting
    uint256 public maxRoundTripOvershoot;               // CT5: max (back − amt) over a round-trip

    uint256 internal constant DUST = 1;
    uint256 internal constant CAP = 1e24;
    uint256 internal constant RATE = 1e18;
    // CT4 tolerance: a single truncation floor(tokens·rate/1e18) loses <1 wei underlying. DERIVED from the
    // structure of the redeem formula (not tuned): the contract and the external computation yield the SAME
    // floor at a consistent rate; the accrual delta is covered by the [rateLo,rateHi] band. Residual ≤ one mantissa(1e18) truncation.
    uint256 internal constant REDEEM_TOL = 1;

    constructor(ICToken c, MockERC20 t, address[] memory a) {
        cToken = c;
        token = t;
        actors = a;
        attacker = a[0];
    }

    function holdersLength() external view returns (uint256) {
        return holders.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _fund(address a, uint256 amount) internal {
        token.mint(a, amount);
        if (a == attacker) fundedAttacker += amount;
        vm.prank(a);
        token.approve(address(cToken), type(uint256).max);
    }

    function _track(address a) internal {
        if (!seenHolder[a] && cToken.balanceOf(a) > 0) {
            seenHolder[a] = true;
            holders.push(a);
        }
    }

    /// CT1 proof (conservation, public getters): profit = (underlying on hand + value of shares) − credited.
    function _recordProfit() internal {
        uint256 shares = cToken.balanceOf(attacker);
        int256 wealth = int256(token.balanceOf(attacker) + shares * cToken.exchangeRateStored() / RATE);
        int256 p = wealth - int256(fundedAttacker);
        if (p > maxProfitSeen) maxProfitSeen = p;
    }

    /// Attack precondition: a tiny FIRST mint by the attacker into an EMPTY market. Called ONCE in setUp,
    /// EXCLUDED from the fuzz selectors (targetSelector in InvariantBase) - not a repeatable action.
    function seedFirstMint(uint256 amount) external {
        _fund(attacker, amount);
        vm.prank(attacker);
        cToken.mint(amount);
        _track(attacker);
        _recordProfit();
    }

    // ---- actions (fuzz selectors) ----

    function mintAct(uint256 aSeed, uint256 amt) public {
        address a = _actor(aSeed);
        amt = bound(amt, DUST, CAP);
        _fund(a, amt);
        uint256 before = cToken.balanceOf(a);
        vm.prank(a);
        uint256 code = cToken.mint(amt);
        uint256 minted = cToken.balanceOf(a) - before;
        // CT2 (probe): a successful meaningful mint must not yield 0 shares
        if (amt >= DUST && code == 0 && minted == 0) roundToZeroSeen = true;
        _track(a);
        _recordProfit();
    }

    /// CT1 core: the attacker donates via a RAW transfer directly to the cToken (bypassing mint). Without it the bug is unreachable.
    function donateAct(uint256 amt) public {
        amt = bound(amt, 1, CAP);
        token.mint(attacker, amt);
        fundedAttacker += amt;                           // the donation is assets credited to the attacker
        vm.prank(attacker);
        token.transfer(address(cToken), amt);
        _recordProfit();
    }

    function redeemAct(uint256 aSeed, uint256 tokens) public {
        address a = _actor(aSeed);
        uint256 bal = cToken.balanceOf(a);
        if (bal == 0) return;
        tokens = bound(tokens, 1, bal);
        _redeemHonored(a, tokens);
        _track(a);
        _recordProfit();
    }

    /// CT4 (control): redeem ALL held shares - the same amount-honesty check.
    function redeemAllAct(uint256 aSeed) public {
        address a = _actor(aSeed);
        uint256 bal = cToken.balanceOf(a);
        if (bal == 0) return;
        _redeemHonored(a, bal);
        _track(a);
        _recordProfit();
    }

    /// CT4 (control, fund-safety): redeem does NOT silently short-change. A shift from liveness ("does not revert")
    /// to AMOUNT honesty: on success (err==0) the underlying received == burned shares·exchangeRate (within the rate
    /// band before/after - accrual-safe, since accrual only grows the rate), and shares and totalSupply are reduced
    /// by exactly redeemTokens. A REVERT OR a non-zero error code = the protocol declined (e.g. a legitimate cash guard
    /// getCash()<owed) - safe behavior, NOT theft → HOLD. Everything from PUBLIC getters, answer-agnostic.
    /// Boundary: distinguishing a buggy DoS-redeem from a legitimate cash refusal from public state alone is
    /// impossible without answer-awareness → the liveness aspect is NOT taken (any non-success = HOLD).
    function _redeemHonored(address a, uint256 tokens) internal {
        uint256 rate0 = cToken.exchangeRateStored();
        uint256 ts0 = cToken.totalSupply();
        uint256 under0 = token.balanceOf(a);
        vm.prank(a);
        try cToken.redeem(tokens) returns (uint256 err) {
            if (err != 0) return;                        // Compound-style decline without revert → HOLD
            uint256 rate1 = cToken.exchangeRateStored();
            uint256 received = token.balanceOf(a) - under0;
            // share accounting - EXACT, no tolerance
            if (ts0 - cToken.totalSupply() != tokens) redeemViolation = true;
            // fair amount - within the rate band before/after ± a single truncation (REDEEM_TOL)
            uint256 rateLo = rate0 < rate1 ? rate0 : rate1;
            uint256 rateHi = rate0 < rate1 ? rate1 : rate0;
            uint256 lo = tokens * rateLo / RATE;
            uint256 hi = tokens * rateHi / RATE;
            if (received + REDEEM_TOL < lo) redeemViolation = true;
            if (hi + REDEEM_TOL < received) redeemViolation = true;
        } catch {
            // revert = safe behavior (legitimate cash guard etc.) → HOLD, leave the flag untouched
        }
    }

    /// CT5 (D₂): a mint→redeem round-trip by one actor must not return more than deposited beyond dust.
    function roundTrip(uint256 aSeed, uint256 amt) public {
        address a = _actor(aSeed);
        amt = bound(amt, DUST, CAP);
        _fund(a, amt);
        uint256 before = cToken.balanceOf(a);
        vm.prank(a);
        cToken.mint(amt);
        uint256 sh = cToken.balanceOf(a) - before;
        if (sh == 0) {
            _track(a);
            _recordProfit();
            return;
        }
        uint256 uBefore = token.balanceOf(a);
        vm.prank(a);
        cToken.redeem(sh);
        uint256 back = token.balanceOf(a) - uBefore;
        if (back > amt && back - amt > maxRoundTripOvershoot) maxRoundTripOvershoot = back - amt;
        _track(a);
        _recordProfit();
    }
}
