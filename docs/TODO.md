# Nonprofiteer — TODO

Status: **app scaffolded + quality gate in place; the Phase-1 data model is in
(Organization / Address / Filing / Person); BMF ingest has landed** (org spine — download,
header-pinned parse, idempotent upsert, fan-out, run log). Next up is the 990 Part VII parse.
This tracks the path to a running Phase 1 (BMF ingest + 990 Part VII parse → changed-since
sync feed). See [DECISIONS.md](DECISIONS.md) for the locked reasoning behind each item.

Phase 1 scope is the **ohfec-useful slice**: org spine + people/addresses, served over the
sync feed. All financial schedules are Phase 2.

## Critical path

~~Scaffold~~ → resolve cursor + parse-location decisions → ~~data model~~ → ~~BMF ingest~~ →
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

- [x] **Organization** — surrogate primary id; EIN as indexed (non-unique) attribute,
  cardinality 0/1/many; explicit central-vs-subordinate self-reference (D7). Domain
  `Nonprofiteer.Orgs`; migration + snapshots generated.
- [x] **Filing** — one per submitted return (990/990-EZ/990-PF) per tax year; belongs_to Org;
  `source_object_id` provenance pointer (D11); indexed on `organization_id`/`tax_year`.
- [x] **Person** — Part VII people: `name`, `title`, belongs_to Org + Filing + (optional)
  Address. (Compensation/tenure = Phase 2.)
- [x] **Address** — normalized; attached to orgs and people (via Part VII).
- [x] Bake in the **corroboration guarantee** — Org ships address + EIN (where present);
  Person ships address + source-filing pointer (belongs_to Filing, required) (D8). *(Structure
  in place; non-null-where-present enforcement lands with ingest validations.)*
- [x] Bake in **history** — `superseded_by` self-pointer + `:tombstone` soft-delete + no hard
  `:destroy` on Organization, Filing, and Person (D10).
- [x] **Port `nonprofiteer.resources` mix task** — Ash introspection over `:nonprofiteer,
  :ash_domains` (`mix nonprofiteer.resources [Name]`), with tests.

## BMF ingest (the org spine, no XML)

- [x] Oban job: download EO BMF CSV → upsert `organizations` (identity, address, NTEE, group).
  `BmfExtractWorker` fetches via `Ingest.Client` (Req, stubbable), parses via `Ingest.Bmf`
  (header-pinned, raises `LayoutError` on drift), upserts on the partial `:unique_bmf_ein`
  identity (D12), links/updates each org's address in place, and writes an `Ingest.Run` audit
  row on success *and* failure. Central/subordinate wiring off `gen` (GEN) is a later
  reconcile pass — the column is captured, not yet linked.
- [x] Handle the state-split extracts — `BmfCoordinatorWorker` (monthly cron) fans out one
  `BmfExtractWorker` per **per-state** file (50 states + DC + `pr` + international `xx` = 53),
  verified live against irs.gov 2026-07 (D13). URL pattern `/pub/irs-soi/eo_<code>.csv`.
- [x] Monthly cadence — `Oban.Plugins.Cron`, `:ingest_bulk` queue (concurrency 4).
- [x] Capture `AFFILIATION` on `Organization` (`affiliation_code`) — distinguishes a group's
  central (6/8) from its subordinates (9); prerequisite for the reconcile below (D13).
- [x] **GEN→central reconcile** — `BmfReconcileWorker`, a *global* post-ingest pass (monthly
  cron, day after the fan-out): builds a `gen`→central map from `affiliation_code in (6, 8)`
  orgs, streams subordinates (`= 9`) and sets `central_org_id`, counting GENs whose central
  isn't in the dataset as unresolved (D7/D13). Idempotent (only writes on change); logs an
  `Ingest.Run` (`extract_id: "reconcile"`).

**Follow-ups surfaced by this slice:**
- [ ] Track `:partial` run status (mid-batch failure count), not just `:success`/`:failure`.
- [ ] Reconcile: handle >1 central sharing a GEN (currently last-wins) — count/flag the anomaly.
- [ ] Reconcile perf: if per-row subordinate updates get slow at national scale, move to a
  set-based `UPDATE … FROM` (accepting the Ash-action bypass for a pure FK set).
- [ ] Re-capture `test/fixtures/bmf/` periodically from real files and diff, to catch layout
  drift deliberately.

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
