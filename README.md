# Nonprofiteer

An affordable, open alternative to GuideStar: public IRS Form 990 data turned into a
browsable resource and a clean API.

Early / **infrastructure-first** (near-term goal: feed the sibling
[ohfec](docs/VISION.md#why-ohfec-needs-this-concretely) campaign-finance project; public
product later). The Phoenix + Ash app is scaffolded and boots; domain code (Ash resources,
ingest, sync feed) is not written yet. See the docs:

- [Vision](docs/VISION.md) — problem, users, positioning, infra-first framing.
- [Decisions](docs/DECISIONS.md) — locked decisions + reasoning (start here for the "why").
- [Data Sources](docs/DATA-SOURCES.md) — 990 source analysis + ingestion strategy/phasing.
- [Future Sources](docs/FUTURE-SOURCES.md) — catalog of supplementary sources beyond 990.
- [Architecture](docs/ARCHITECTURE.md) — Elixir / Phoenix / Ash system design + sync feed.

## Development

Stack: Elixir 1.20 / OTP 29, Phoenix 1.8, Ash 3 (`ash_postgres`, `ash_phoenix`,
`ash_admin`), Oban, Postgres with `pg_trgm`.

```sh
mix setup       # deps + create/migrate DB (ash.setup) + assets
mix phx.server  # run the app
bin/check       # quality gate — run before considering work done
```

DB config is env-driven — defaults to your OS user (`$USER`) with no password. Override with
`DB_USERNAME` / `DB_PASSWORD` / `DB_HOST` / `DB_PORT`.

### Quality gate

`bin/check` wraps the `check` alias in [`mix.exs`](mix.exs) (the single source of truth) and
only reformats output — collapsing green steps and surfacing the decisive lines on failure.
The alias runs, in order, and stops at the first failure:

| Step | Command | Enforces |
|------|---------|----------|
| Format | `mix format --check-formatted` | Code matches `mix format`; no unformatted files. |
| Lint | `mix credo --strict` | Credo static analysis at strict level. |
| Docs | `mix doctor --raise` | Module/function doc + doctest coverage per [`.doctor.exs`](.doctor.exs). |
| Compile | `mix compile --warnings-as-errors --force` | Clean full recompile — any warning fails. |
| Tests + coverage | `mix coveralls` | Full test suite plus ≥ minimum coverage in [`coveralls.json`](coveralls.json). |

`coveralls` runs the suite *and* enforces the coverage floor, so it stands in for a plain
`test` step rather than running the tests twice. It runs under `MIX_ENV=test` via the
`preferred_envs` in `mix.exs`.

Both [`.doctor.exs`](.doctor.exs) and [`coveralls.json`](coveralls.json) exempt the untouched
phx.new / igniter scaffold (core components, error views, endpoint, etc.). **Remove an
exemption as its file gains hand-written code** — don't widen the patterns, or real code
skips the gate silently.

## AI tooling

This repo is configured for AI-assisted development. A `SessionStart` hook
(`.claude/settings.json`) loads caveman response mode automatically each session; say
`stop caveman` or `normal mode` to disable it for a session.
