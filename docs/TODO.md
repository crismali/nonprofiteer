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
- **Licensing/ToS** — reviewed (D18 / [LICENSING.md](LICENSING.md)): IRS public domain + Data
  Lake ODbL (compatible with our open posture), ProPublica excluded. Counsel sign-off still
  needed before a paid launch.

## Resolve open decisions — all resolved

From [DECISIONS.md](DECISIONS.md); kept as a record of the Phase-1 forks and where they landed.

- [x] **Sync cursor mechanism** — monotonic `updated_at`, keyset, safety-lag watermark (D16).
- [x] **API layer** — AshJsonApi (D17).
- [x] **XML parsing home** — in-BEAM Saxy; IRSx as offline validator (D14).
- [x] **Licensing/ToS review** — D18 / [LICENSING.md](LICENSING.md).
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
- [x] Track `:partial` run status (mid-batch failure count) in `BmfExtractWorker` — a tolerant
  `Ingest.Batch.reduce/3` fold keeps the committed-row count when a row fails partway, so the
  audit row reads `:partial` (some orgs in) vs `:failure` (none) instead of hiding landed rows.
  - [ ] Adopt the same in `BmfReconcileWorker` — deferred (confirmed 2026-07-06): reconcile's
    `central_map` is built from live DB reads *inside* `perform`, so it can never hold a bogus
    central id — the only per-row failure is a DB fault (connection death), uninducible without
    mocking Ash/Repo. Code-only symmetry with `BmfExtractWorker` has no honest test, so left as-is.
- [x] Reconcile: handle >1 central sharing a GEN — was silent last-wins (also read-order
  dependent, so non-deterministic across runs); now picks the lowest-EIN central deterministically
  and logs a warning naming the ambiguous GEN(s).
- [ ] Reconcile perf: if per-row subordinate updates get slow at national scale, move to a
  set-based `UPDATE … FROM` (accepting the Ash-action bypass for a pure FK set).
- [x] Layout-drift canary — `mix nonprofiteer.capture_known_answers` already re-captures a real
  irs.gov extract into `test/fixtures/known_answers/bmf_dc_known.csv`; a `bmf_test` now runs the
  pinned parser against that live header, so a re-capture that picks up an IRS layout change fails
  loud (deliberate diff) instead of waiting for a production `BmfExtractWorker` to raise.
  (`eo_sample.csv` stays hand-crafted — it backs the known-answer value assertions, can't be a
  live canary.)

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
- [x] Validate output against **IRSx** as reference (documented dev-time diff, not CI) — see the
  cross-check task below.

**Deferred (Phase-1 follow-ups, not the first cut):**
- [x] **Amendment supersede (D10)** — `EfileSupersedeWorker` points earlier filings'
  `superseded_by` at the latest by `filed_on` within each `(organization, tax_year,
  return_type)` group; landed with the sync feed (D17).
- [ ] **990-EZ / 990-PF** Part VII/officer extraction (different elements than Form 990); index
  worker filters to Form 990 today.
- [x] **Stream the all-years index** — `Client.stream!` (Req `into: :self`) + `Index.parse_stream`
  (chunk→line reassembly → lazy `NimbleCSV.parse_stream`); the worker filters/chunks/enqueues in
  1k batches and narrows the ingested-id diff to each batch's object ids (`IN (...)`). Memory is
  now bounded by batch size, not the corpus.
- [x] Foreign filers (`ForeignAddress`) — the Part VII parser now reads `ForeignAddress`
  (`ProvinceOrStateNm`/`CountryCd`/`ForeignPostalCd`) as well as `USAddress`; a return with
  neither yields an all-nil address instead of a false `country: "US"`.
- [x] Coverage/quality metrics off the data (`mix nonprofiteer.coverage`): % orgs with EIN /
  address / parsed Part VII people, % filings & people populated, per-source run summary.
- [ ] Older-schema (pre-2013) Part VII support, if history is extended past the D9 window.
- [x] IRSx cross-check script (dev-time diff of our parse vs. IRSx on the fixtures) —
  `mix nonprofiteer.irsx_crosscheck` seeds a throwaway IRSx cache with each known-answer return
  and diffs Part VII Section A listees (name/title, in order) against `Efile.PartVii`; pure
  extraction + compare in `Ingest.Efile.IrsxCrosscheck` (unit-tested), task shells to `irsx` and
  skips gracefully if it's not installed. Verified: both flagship returns match IRSx 15/15.

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
- [ ] Confirm the feed contract end-to-end into ohfec (the known-answer validation below).
- [ ] Auth / rate-limiting in front of the feed — see **API / serving expansion** below
  (API keys supersede the earlier interim-Basic-auth idea).

## API / serving expansion

Beyond the changed-since sync feed, the API surface consumers touch. Suggested order:
health → API keys → lookup/search → raw-source access. All are post-Phase-1 product work.

- [ ] **Register a domain name** — pick + register the public hostname for nonprofiteer. Blocks
  a real deploy and fixes the production base URL, which becomes the OpenAPI `servers[].url`
  (`mix nonprofiteer.openapi`, `GET /api/v1/open_api`) that ohfec's generated client targets —
  so nail it down before handing ohfec a spec pinned to a throwaway host.
- [x] **Health endpoint** — `GET /health` (`HealthController`), **unauthenticated**, no pipeline
  (no `:accepts`/CSRF) so bare monitors get a response. 200 + `database` reachability + newest
  `last_ingest_run_at` (the run lookup doubles as the DB probe); 503 if the probe fails.
- [ ] **Admin-managed API keys** — an `ApiKey` Ash resource (hashed key, owner, active flag,
  maybe tier) managed via AshAdmin, plus an auth plug on the `/api/v1` pipeline. Use
  `ash_authentication`'s API-key strategy, don't hand-roll. Foundation for traffic management +
  the affordability tiers (VISION); **supersedes the interim-Basic-auth idea** (per-consumer
  keys beat a shared password). Rate-limiting is a separate layer keyed on the authenticated key.
- [ ] **Lookup / search endpoints** ("public API, later" — ARCHITECTURE) — org-by-EIN / by-id
  (trivial AshJsonApi `get` route) + name/NTEE search (a `pg_trgm` read action; the extension
  is already installed). Gate behind API keys, so land these *after* keys.
- [ ] **Raw-source access** — expose the mirrored source 990 XML (D11) for provenance/trust and
  maximal openness (the XML content is IRS public domain — the safest thing we redistribute).
  `GET /api/v1/filings/:id/source` streaming/redirecting the R2-mirrored document; `source_object_id`
  is already the pointer. **Depends on R2 being populated** by a real ingest run, so naturally
  later. (BMF isn't worth exposing — it's a public irs.gov CSV; the per-filing XML is the
  valuable, hard-to-locate one.)
- [x] **Strip internal doc references from resource `description` fields** — the exposed
  descriptions (public attributes, the `:changed_since` action, `event_type`) are now
  consumer-facing; the `D#` refs + ingest jargon moved to adjacent code comments. Audited
  against the generated spec (`mix nonprofiteer.openapi`). Relationship and non-routed action
  descriptions (`upsert_from_bmf`/`upsert_from_efile`) don't reach OpenAPI, so their rationale
  stays put.

## Validation (build early — silent-failure guard)

- [x] **Known-answer fixtures** (nonprofiteer half) — real 501(c)↔committee bridges asserted
  end-to-end through BMF→Part VII: American Action Network (Conston→Congressional Leadership
  Fund, shared officer) + American Action Forum (shared 1747 Pennsylvania Ave address). See
  [EXAMPLES.md](EXAMPLES.md) + `known_answers_test`; re-capture via
  `mix nonprofiteer.capture_known_answers`. Already caught a real bug (BOM parse skip).
- [ ] **Close the loop into ohfec** — verify the documented FEC match (the committee half)
  once ohfec's sync consumer + `:exact`/name+address tiers consume the feed. Cross-repo.
- [ ] Add a couple more known-answer cases for breadth (another shared-officer + shared-address
  pair beyond the flagship ecosystem).
- [x] **Coverage/quality metrics** — `mix nonprofiteer.coverage`: % orgs with EIN / address /
  parsed Part VII people, % filings & people populated, per-source run summary. *(Dedupe /
  amendment-correctness metrics still a possible extension.)*

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
