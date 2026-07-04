# Nonprofiteer — TODO

Status: **planning complete, no application code yet.** This tracks the path from planning
to a running Phase 1 (BMF ingest + 990 Part VII parse → changed-since sync feed). See
[DECISIONS.md](DECISIONS.md) for the locked reasoning behind each item.

Phase 1 scope is the **ohfec-useful slice**: org spine + people/addresses, served over the
sync feed. All financial schedules are Phase 2.

## Critical path

Scaffold → resolve cursor + parse-location decisions → data model → BMF ingest →
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

- [ ] `mix` Phoenix + Ash app; mirror sibling **ohfec** structure/conventions.
- [ ] Deps: `ash`, `ash_postgres`, `oban`; enable `pg_trgm` + `tsvector` in Postgres.
- [ ] Test/quality tooling (`mix check` equivalent to ohfec).
- [ ] Populate the "Conventions" section of [CLAUDE.md](../CLAUDE.md) once patterns exist.

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
