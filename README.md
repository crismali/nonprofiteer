# Nonprofiteer

An affordable, open alternative to GuideStar: public IRS Form 990 data turned into a
browsable resource and a clean API.

Early / planning stage — **infrastructure-first** (near-term goal: feed the sibling
[ohfec](docs/VISION.md#why-ohfec-needs-this-concretely) campaign-finance project; public
product later). See the docs:

- [Vision](docs/VISION.md) — problem, users, positioning, infra-first framing.
- [Decisions](docs/DECISIONS.md) — locked decisions + reasoning (start here for the "why").
- [Data Sources](docs/DATA-SOURCES.md) — 990 source analysis + ingestion strategy/phasing.
- [Architecture](docs/ARCHITECTURE.md) — Elixir / Phoenix / Ash system design + sync feed.

## AI tooling

This repo is configured for AI-assisted development. A `SessionStart` hook
(`.claude/settings.json`) loads caveman response mode automatically each session; say
`stop caveman` or `normal mode` to disable it for a session.
