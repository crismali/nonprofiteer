# EXAMPLES.md — known-answer validation cases

Real nonprofit↔committee bridges used as **known-answer fixtures** (ARCHITECTURE "Validation").
Each case pins what Nonprofiteer's pipeline must emit for a *documented* dark-money↔FEC overlap,
so a silent Part VII parse regression (bugs here fail silently) shows up as a failing assertion.
The nonprofit half is asserted in [`test/nonprofiteer/known_answers_test.exs`](../test/nonprofiteer/known_answers_test.exs);
the FEC half is the target for ohfec's matcher once its sync consumer lands.

Fixtures are captured from live IRS sources by `mix nonprofiteer.capture_known_answers` (re-run
and diff to catch upstream drift). The bridge to campaign finance mirrors the "House Republicans
stack" in ohfec's [`docs/EXAMPLES.md`](../../ohfec/docs/EXAMPLES.md) — the 501(c)(4)/(c)(3)
blind spot that Nonprofiteer's 990 data fills.

> **Why the match is name+address, not EIN:** FEC committees carry no EIN, so the nonprofit↔
> committee bridge fires on a shared officer name and/or shared address — EIN corroborates only
> when both sides have one (D8/D15). These cases exercise both overlap types.

## Case 1 — American Action Network (shared-officer bridge)

- **Nonprofit:** American Action Network Inc, a 501(c)(4). **EIN 27-0730508.** Form 990, TY2020,
  OBJECT_ID `202201369349304100`.
- **Nonprofiteer emits (asserted):** org sourced from BMF (`AMERICAN ACTION NETWORK INC`); a
  Form-990 filing; 15 Part VII people including **Daniel Conston — President** (sequence 0);
  filer address `1747 Pennsylvania Avenue NW 5th fl`, Washington, DC.
- **FEC target:** **Congressional Leadership Fund** (Super PAC, committee `C00504530`). Daniel
  Conston is its president — the documented officer overlap.
- **Expected ohfec match:** `:strong` on the shared officer name (+ address corroboration); not
  `:exact`, since the committee has no EIN.

## Case 2 — American Action Forum (shared-address bridge)

- **Nonprofit:** American Action Forum Inc, a 501(c)(3) — the (c)(4)'s sibling. **EIN
  27-0567765.** Form 990, TY2021, OBJECT_ID `202311359349309026`.
- **Nonprofiteer emits (asserted):** org sourced from BMF; 15 Part VII directors; filer address
  `1747 PENNSYLVANIA AVE NW 5TH FLOO`, Washington, DC.
- **The bridge:** the **same 1747 Pennsylvania Ave office** as American Action Network (and the
  wider ecosystem). Note the two raw address strings — `1747 Pennsylvania Avenue NW 5th fl` vs
  `1747 PENNSYLVANIA AVE NW 5TH FLOO`. They only match **after normalization**, which is exactly
  why Nonprofiteer stores raw and the consumer normalizes (D2/D4/D15): the source of truth keeps
  both verbatim; ohfec's `EntityResolution` collapses them.

## What this caught

Case 1 immediately surfaced a real parser bug: the AAN return ships with a leading UTF-8 **BOM**,
which Saxy rejected — so the whole return was being *silently skipped* as unparseable. Exactly
the failure mode the known-answer guard exists for. Fixed by stripping the BOM in `Efile.PartVii`.
