# Nonprofiteer — TODO

Status: **Phase-1 pipeline is functionally complete.** Data model (Organization / Address /
Filing / Person) + BMF ingest (org spine) + 990 Part VII parse (people/addresses, R2 mirror,
index-driven fan-out) + the changed-since **sync feed** (AshJsonApi at `/api/v1/sync/...`,
D16/D17) with amendment supersede all landed. What remains is hardening/breadth (see
follow-ups throughout) and the **known-answer validation** end-to-end into ohfec. See
[DECISIONS.md](DECISIONS.md) for the locked reasoning behind each item.

Phase 1 scope is the **ohfec-useful slice**: org spine + people/addresses, served over the
sync feed. All financial schedules are Phase 2.

## Critical path

~~Scaffold~~ → ~~data model~~ → ~~BMF ingest~~ → ~~Part VII parse~~ → ~~sync feed~~.
Phase-1 critical path is **complete**; validation fixtures (end-to-end into ohfec) are the
remaining correctness guard.

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

Scope (agreed): Part VII Section A **people only** (name/title/address), **modern schema
(2013+) only** (older = loud-skip + count, matches D9's ~3-year window), **in-BEAM Saxy**
parse with IRSx as an offline reference validator (not in the pipeline/CI). Names + addresses
stored **raw** (consumer normalizes — D2/D4); only the **EIN** is canonicalized as an
identifier (`Ingest.Ein.normalize/1`). Orphan filings (EIN not in the BMF spine) are
**skipped + counted**, not force-created.

- [x] Pull 990 XML + index files from the **GivingTuesday Data Lake** (`gt990datalake-rawdata`)
  — `Efile.Index` parses `Indices/990xmls/...csv`; XML at `EfileData/XmlFiles/{id}_public.xml`.
- [x] `Efile.PartVii` Saxy parser — Part VII Section A only, no financial schedules; version-
  guarded (`UnsupportedReturnError`, never silent-empty). Form 990 + modern schema (D14/D15).
- [x] `Ingest.Ein.normalize/1` — digits-only, require 9; shared by BMF + e-file at the org
  lookup/identity boundary. BMF retrofitted.
- [x] Mirror each source XML into our own object storage (D11) — `Ingest.ObjectStore` (lifted
  from ohfec's R2 uploader); dormant if unconfigured, required precondition when configured.
- [x] Backfill ~3 filing years up front + going forward (D9) — the index worker's first run
  backfills the window (`efile_min_tax_year`); later runs are incremental (full-snapshot diff).
- [x] Incrementality via Data Lake index files — `EfileIndexWorker` diffs against ingested
  `source_object_id`s and fans out one `EfileParseWorker` per new Form 990.
- [ ] Validate output against **IRSx** as reference (documented dev-time diff, not CI).

**Deferred (Phase-1 follow-ups, not the first cut):**
- [x] **Amendment supersede (D10)** — `EfileSupersedeWorker` points earlier filings'
  `superseded_by` at the latest by `filed_on` within each `(organization, tax_year,
  return_type)` group; landed with the sync feed (D17).
- [ ] **990-EZ / 990-PF** Part VII/officer extraction (different elements than Form 990); index
  worker filters to Form 990 today.
- [ ] **Stream the all-years index** (Req `into:` + `NimbleCSV.parse_stream`) and narrow the
  ingested-id diff — it's fetched/parsed whole today, a memory risk on a small VPS at full
  national volume.
- [ ] Foreign filers (`ForeignAddress`) — parser handles `USAddress`; `xx` extract addresses
  fall through to nil today.
- [ ] Coverage/quality metrics off the data (% orgs with parsed Part VII, orphan/unsupported
  rates) rather than per-filing run rows.
- [ ] Older-schema (pre-2013) Part VII support, if history is extended past the D9 window.
- [ ] IRSx cross-check script (dev-time diff of our parse vs. IRSx on the fixtures).

## Sync feed (the Phase-1 deliverable)

Cursor decided (D16), layer AshJsonApi (D17): monotonic **`updated_at`**, keyset
`(updated_at, id)`, bounded by a safety-lag watermark; event type derived from row state.

- [x] Generic, per-resource **changed-since** feed (D3/D17) — AshJsonApi at
  `/api/v1/sync/{organizations,people,filings,addresses}`, keyset-paginated (`page[after]` is
  the cursor); first page with no cursor is the bulk snapshot.
- [x] Bound the feed by the watermark (`Ingest.SyncWatermark`, safety lag — D16/D17) via the
  shared `ChangedSince` preparation, so in-flight writes aren't served mid-ingest.
- [x] Derive **upsert / supersede / tombstone** event type from row state (`tombstoned_at` /
  `superseded_by_id`) — `event_type` calculation, rendered in each record (D10/D16).
- [x] Land **amendment supersede** — `EfileSupersedeWorker` (cron after the parse); composes
  with the feed for free (setting `superseded_by` bumps `updated_at`).

**Follow-ups:**
- [ ] **Interim Basic auth in front of the feed** — reads are unauthenticated *by design* long
  term (ARCHITECTURE), but during early access we likely want the whole API gated behind Basic
  auth (fail-closed, TLS-terminated in front) while ohfec is the only consumer, before public
  tiers exist. Mirror ohfec's `SiteAuth` interim gate; enable via config, off in dev/test.
- [ ] Confirm the feed contract end-to-end into ohfec (the known-answer validation below).
- [ ] Rate-limit / API tiers (Phase 3).

## Validation (build early — silent-failure guard)

- [ ] **Known-answer fixtures** — real nonprofit↔committee pairs sharing an officer/address,
  verified end-to-end into ohfec. Borrow candidates from ohfec's `docs/EXAMPLES.md`.
- [ ] **Coverage/quality metrics** — % orgs with parsed Part VII; null rates on
  name/address/EIN; dedupe/amendment correctness.

## Deferred (Phase 2+)

- Full financial schedules; then Schedule I (grants out) + Schedule R (related orgs).
- Public JSON API tiers + thin LiveView UI.
- **Normalization as a consumer/API concern** — nonprofiteer stores raw (names/addresses
  verbatim, EIN canonicalized as the only identifier); normalization for matching stays out of
  the source of truth (D2/D4). Idea to explore: a **shared normalization library** depended on
  by both ohfec and nonprofiteer, surfaced as an **opt-in API option** (e.g. `?normalized=true`)
  so consumers can request normalized values without the stored facts being mangled.
  - **Trigger to revisit:** if nonprofiteer ever needs to normalize for a *nonprofiteer-specific*
    reason (e.g. its own dedupe/search beyond `pg_trgm`, not just serving ohfec), treat that as
    the signal to **extract ohfec's normalization into that shared library** rather than
    reimplementing it here — so both projects (and future ones like them) share one
    implementation. Don't copy ohfec's normalizer in; lift it out.
- Supplementary sources — see [FUTURE-SOURCES.md](FUTURE-SOURCES.md).
