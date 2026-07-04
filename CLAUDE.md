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

**Early / planning stage — infrastructure-first.** No application code yet. Near-term goal
is feeding the sibling ohfec project, not a public launch. Intended stack: Elixir +
Phoenix + Ash + `ash_postgres` + Oban + `pg_trgm` (mirrors ohfec). Build/test commands and
conventions land here once the app is scaffolded.

**Phase 1 scope:** BMF ingest (orgs) + 990 Part VII parse (people/addresses) only, served
over a generic changed-since sync feed. Financial schedules deferred to Phase 2. See
[DECISIONS.md](docs/DECISIONS.md).

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

_TBD — populate when the app is scaffolded (mix tasks, Ash resource patterns, ingest
pipeline, testing/`mix check`)._
