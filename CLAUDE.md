# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this is

**Nonprofiteer** — an affordable, open alternative to GuideStar: public IRS Form 990 data
turned into a clean, normalized dataset with a browsable resource and API on top. It is a
**use-agnostic source of truth** — it models 990 data and knows nothing about how
consumers use it. See the docs:

- [docs/VISION.md](docs/VISION.md) — problem, users, positioning, infra-first framing.
- [docs/DECISIONS.md](docs/DECISIONS.md) — **locked decisions + reasoning; read first.**
- [docs/DATA-SOURCES.md](docs/DATA-SOURCES.md) — 990 source analysis + ingestion phasing.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Elixir/Phoenix/Ash design + sync feed.

## Status

**Early / infrastructure-first.** App is **scaffolded** (Phoenix + Ash, boots clean) but has
**no domain code yet** — no Ash resources, ingest, or sync feed. Near-term goal is feeding
the sibling ohfec project, not a public launch. Stack: Elixir 1.20 / OTP 29 + Phoenix 1.8 +
Ash 3 (`ash_postgres`, `ash_phoenix`, `ash_admin`) + Oban, Postgres with `pg_trgm`.

**Phase 1 scope:** BMF ingest (orgs) + 990 Part VII parse (people/addresses) only, served
over a generic changed-since sync feed. Financial schedules deferred to Phase 2. See
[DECISIONS.md](docs/DECISIONS.md). Next build step is the data model (Organization / Filing /
Person / Address resources); see [docs/TODO.md](docs/TODO.md).

## Sibling project: ohfec

Nonprofiteer's driver is **ohfec** (`~/Development/public-data-projects/ohfec`, sibling dir) — a Phoenix/Ash app
over the OpenFEC campaign-finance API, **same stack**. OpenFEC is blind to
501(c)(4)/(c)(3) dark-money nonprofits; nonprofiteer's 990 data extends money trails past
that blind spot. ohfec's `OhFec.EntityResolution` layer has a dormant EIN-matching tier
waiting for exactly this data. Bridge = fuzzy org name/address match with EIN as
corroboration, over nonprofiteer's public API. Details:
[docs/ARCHITECTURE.md#campaign-finance-integration](docs/ARCHITECTURE.md#campaign-finance-integration).

## AI tooling

A `SessionStart` hook (`.claude/settings.json`) auto-loads **caveman** response mode each
session. Disable per-session with `stop caveman` / `normal mode`. More AI-tooling tuning is
planned.

## Conventions

Mirrors ohfec's **structure and conventions**, but not its dependency versions — prefer the
latest and bump *up* to resolve conflicts rather than pinning down (e.g. `gettext ~> 1.0` to
satisfy `ash_admin`, not pinning `ash_admin` back).

**Setup / commands:**
- `mix setup` — deps, `ash.setup` (create DB + migrate), assets.
- `mix ash.setup` / `mix ash.reset` — DB lifecycle via Ash codegen.
- **`bin/check`** — run before considering work done. Wraps `mix check` (format,
  `credo --strict`, `doctor --raise`, `compile --warnings-as-errors`, `coveralls` at 80%),
  collapsing green output and surfacing decisive lines on failure. Single source of truth is
  the `check` alias in `mix.exs`; `bin/check` only reformats output.
- App modules: `Nonprofiteer` (`:nonprofiteer`) / `NonprofiteerWeb`. Repo is
  `AshPostgres.Repo` with `["ash-functions", "pg_trgm"]` extensions.

**Local Postgres:** dev/test DB config is env-driven (`DB_USERNAME` → `$USER`, no password by
default) — this box's Postgres has no `postgres` role. Override with `DB_*` env vars.

**Quality-gate exemptions:** `.doctor.exs` and `coveralls.json` exempt the untouched
phx.new/igniter scaffold (core_components, error views, endpoint, etc.). **Remove entries as
each file gains hand-written code** — don't widen the patterns, or real code skips the gate
silently.

Ash resource patterns / ingest pipeline conventions land here as that code is written.
