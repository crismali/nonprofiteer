---
name: elixir-types
description: Elixir's set-theoretic type system (1.20) conventions — this project uses it instead of Dialyzer/typespecs
---

# Elixir set-theoretic types

This project uses **Elixir's built-in set-theoretic type system** (completed as of Elixir 1.20, which this project pins — `elixir: "~> 1.14"` in `mix.exs`, but the toolchain runs 1.20/OTP 29) instead of Dialyzer/Dialyxir for static checking. Don't default to writing Dialyzer-era `@spec`s and assuming a Dialyzer pass will check them; there is no Dialyzer step in `mix check`/CI here.

## What actually checks types here

- The compiler itself, via `mix compile --warnings-as-errors --force` — this is the type-checking gate (part of `mix check` / `bin/check`), not a separate `mix dialyzer` step. Type mismatches the compiler can infer (pattern-match exhaustiveness, function clause coverage, struct field access) surface as compile warnings and fail the build.
- This is **gradual** typing: the compiler infers and checks what it can from code structure (pattern matches, guards, struct usage) without requiring exhaustive `@spec` annotations everywhere. Don't assume untyped code is silently unchecked — structural inference still catches real mismatches.

## `@doc`/`@spec` conventions in this project

Doc coverage is enforced by `mix doctor --raise` (see [`.doctor.exs`](../../../.doctor.exs)) — public modules/functions need `@doc`/`@moduledoc` unless the file is on the scaffold exemption list. `@spec` is **not** required by the gate; add it "where the type system doesn't already make it redundant":

- Skip `@spec` when the function's type is fully obvious from its `@doc`/name and the compiler already infers it correctly (e.g. a function that just delegates or pattern-matches a struct field).
- Write `@spec` when the function has a non-obvious return shape (e.g. `{:ok, t()} | {:error, Ash.Error.t()}`-style unions), or when you want the type explicit for documentation even if inference would catch a mismatch anyway.
- Don't add `@spec` purely as Dialyzer-era ritual — if it adds no information and isn't load-bearing for the compiler, leave it out.

## Verifying an Ash-heavy module

Ash itself may still carry Dialyzer-oriented typespecs internally depending on the Ash version installed (Ash 3.x; this project tracks the latest rather than pinning down — see [CLAUDE.md](../../../CLAUDE.md) deps convention). **Verify rather than assume** when something Ash-generated looks like it's fighting the new type system (e.g. a generated action's inferred return type looking wider than expected). Check `mix compile --warnings-as-errors` output directly rather than guessing whether Ash's own typing conventions interoperate cleanly.

## Practical checks

- `mix compile --warnings-as-errors --force` is the authoritative check — run it (or `bin/check`) after any signature-shaping change (new pattern match arm, new union return type) rather than assuming a Dialyzer-style "no errors" pass would have meant the same thing.
- If a change needs real type-narrowing help (e.g. a calculation or change module with a genuinely ambiguous return), prefer adding/tightening a pattern match or guard over reaching for a workaround typespec — the set-theoretic system's strength is inferring from how values are actually used, not from annotations alone.
