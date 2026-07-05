# Nonprofiteer — TODO

Status: **app scaffolded + quality gate in place; no domain code yet.** This tracks the path
to a running Phase 1 (BMF ingest + 990 Part VII parse → changed-since sync feed). See
[DECISIONS.md](DECISIONS.md) for the locked reasoning behind each item.

Phase 1 scope is the **ohfec-useful slice**: org spine + people/addresses, served over the
sync feed. All financial schedules are Phase 2.

## Critical path

~~Scaffold~~ → resolve cursor + parse-location decisions → data model → BMF ingest →
Part VII parse → sync feed. Build validation fixtures throughout, not at the end.

**Biggest risks (from the docs):**
- **Schema-version drift** — Part VII parse bugs fail *silently*; known-answer fixtures are
  the only guard. Build them early.
- **Licensing/ToS** — GivingTuesday Data Lake + ProPublica review blocks any resale/API
  tier. Owner task.

## Resolve open decisions (before schema locks)

From [DECISIONS.md](DECISIONS.md) "Open" + [ARCHITECTURE.md](ARCHITECTURE.md) open questions.

- [ ] **Sync cursor mechanism** — IRS release month vs. monotonic `updated_at`. Must emit
  supersede/tombstone events, not just upserts (D10).
- [ ] **API layer** — Ash-generated (AshJsonApi/AshGraphql) vs. hand-rolled Phoenix JSON.
- [ ] **XML parsing home** — in-BEAM parse vs. separate service reusing IRSx directly.
- [ ] **Licensing/ToS review** — GivingTuesday Data Lake + ProPublica, before any resale.
  *(Owner task.)*

## Scaffold

- [x] `mix` Phoenix + Ash app; mirror sibling **ohfec** structure/conventions. *(Phoenix 1.8 +
  Ash 3 + `ash_postgres`/`ash_phoenix`/`ash_admin` + Oban; boots clean.)*
- [x] Deps: `ash`, `ash_postgres`, `oban`; enable `pg_trgm` in Postgres via `Repo`
  `installed_extensions`. *(`tsvector` is native — no extension; add columns/indexes when a
  resource needs full-text.)*
- [x] Test/quality tooling — `mix check` alias + `bin/check` wrapper (format, `credo --strict`,
  `doctor`, warnings-as-errors, `coveralls` @ 80%).
- [x] Populate the "Conventions" section of [CLAUDE.md](../CLAUDE.md).
- [x] **CI** — GitHub Actions ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml))
  runs `mix check` on push to `main` + all PRs; Postgres 16 service, `deps`/`_build` cache
  keyed on `mix.lock`. (No PLT cache — `check` has no dialyzer step.)
- [x] **Dependency freshness** — audited via `mix hex.outdated`; all deps current. Bumped
  reqs *up* (`tailwind ~> 0.5`, `dns_cluster ~> 0.2`) + `deps.update swoosh dns_cluster
  tailwind`. `tailwind` is the installer only — CSS stays pinned at 3.4.3 (v4 migration is
  separate). Automated freshness (Dependabot/Renovate) still deferred until CI exists.

## Data model (needs its own DATA-MODEL.md)

Ash resources per [ARCHITECTURE.md](ARCHITECTURE.md#data-model-sketch--see-future-data-modelmd).

- [ ] **Organization** — surrogate primary id; EIN as indexed attribute, cardinality
  0/1/many; explicit central-vs-subordinate modeling (D7).
- [ ] **Filing** — one per submitted return per year; source-filing pointer (provenance).
- [ ] **Person** — Part VII officers/directors/key employees: name, role, associated
  address. (Compensation/tenure = Phase 2.)
- [ ] **Address** — normalized; attached to orgs and (via Part VII) people.
- [ ] Bake in the **corroboration guarantee** — every Org/Person ships address + EIN (where
  present) + source-filing pointer (D8).
- [ ] Bake in **history** — `superseded_by` pointer for amendments; soft-delete tombstone
  for withdrawals; never hard-delete (D10).

## BMF ingest (the org spine, no XML)

- [ ] Oban job: download EO BMF CSV → upsert `organizations` (identity, address, NTEE,
  central/subordinate).
- [ ] Handle the state-split extracts (50 states + DC + PR + international).
- [ ] Monthly cadence (matches IRS drop).

## 990 Part VII parse (the deep slice)

- [ ] Pull 990 XML + index files from the **GivingTuesday Data Lake**.
- [ ] Parser driven by the **NODC concordance** — Part VII only, no financial schedules.
- [ ] Validate output against **IRSx** as reference.
- [ ] Mirror each source XML into our own object storage (D11).
- [ ] Backfill ~3 filing years up front + all new filings going forward (D9).
- [ ] Incrementality via Data Lake index files — process only new/changed returns.

## Sync feed (the Phase-1 deliverable)

- [ ] Generic, per-resource **changed-since** feed (D3).
- [ ] Bulk snapshot for first sync, then monthly incrementals.
- [ ] Emit **upsert / supersede / tombstone** events so consumers learn status changes,
  not just new rows (D10).

## Validation (build early — silent-failure guard)

- [ ] **Known-answer fixtures** — real nonprofit↔committee pairs sharing an officer/address,
  verified end-to-end into ohfec. Borrow candidates from ohfec's `docs/EXAMPLES.md`.
- [ ] **Coverage/quality metrics** — % orgs with parsed Part VII; null rates on
  name/address/EIN; dedupe/amendment correctness.

## Deferred (Phase 2+)

- Full financial schedules; then Schedule I (grants out) + Schedule R (related orgs).
- Public JSON API tiers + thin LiveView UI.
- Supplementary sources — see [FUTURE-SOURCES.md](FUTURE-SOURCES.md).
