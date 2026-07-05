---
name: ingest
description: Conventions for Nonprofiteer's data ingest — bulk cold-start vs. incremental, column-layout pinning, idempotent upserts, orphan handling, and known-answer fixtures
---

# Ingest

How data gets into Nonprofiteer: the monthly BMF org spine + incremental 990 Part VII parse, plus the one-time cold-start backfill. Grounded in [ARCHITECTURE.md](../../../docs/ARCHITECTURE.md#data-flow) and [DECISIONS.md](../../../docs/DECISIONS.md). Pairs with the `oban` skill (job/queue mechanics) and `ash` skill (upsert actions).

> Provenance: patterns adapted from the sibling **ohfec** project's `bulk_seed` / `bootstrap` / `fetch_examples` mix tasks. The FEC-specific file names/tiers don't carry over; the mechanics below do.

## What's built (BMF ingest — read these first)

The **BMF org-spine ingest exists** under the `Nonprofiteer.Ingest` domain — the concrete
reference for every principle below:

- **`Nonprofiteer.Ingest.BmfCoordinatorWorker`** — monthly `Oban.Plugins.Cron` entry; fans out
  one extract job per EO BMF file (`Oban.insert_all`). Extract list is overridable via
  `:nonprofiteer, :bmf_extracts` (tests inject a stub extract).
- **`Nonprofiteer.Ingest.BmfExtractWorker`** (`:ingest_bulk` queue) — download → parse →
  upsert → run-log. Idempotent; EIN-less rows counted as orphan skips; writes an `Ingest.Run`
  on both success and failure, reraising so Oban retries.
- **`Nonprofiteer.Ingest.Bmf`** — pure parser; `NimbleCSV.define`d, **header-pinned** (raises
  `Bmf.LayoutError` on drift), returns `%{org: ..., address: ...}` maps. No persistence.
- **`Nonprofiteer.Ingest.Client`** — thin `Req` wrapper reading opts from `:http_req_opts` so
  `Req.Test` stubs it (no real network under test).
- **`Nonprofiteer.Ingest.Run`** — the durable run-log resource.
- Upsert identity is the **partial `:unique_bmf_ein`** on `Organization` (`[:ein] WHERE
  source = 'bmf'`, D12) — the "source's stable key, not global EIN" made concrete. `source` is
  a nullable provenance atom; the 990-XML pass will add its own source value + merge on it.

The 990 Part VII / XML detail pass is **not built yet** — the sections below still describe the
shape to build toward for it.

## Two paths: cold-start vs. steady-state

- **Steady-state (monthly)** never backfills history on its own — the cron ingest only pulls the current IRS drop. Getting from an empty DB to "3 filing years of history" (D9) is a **deliberate one-off**, not something the monthly cadence reaches.
- **Cold-start** is therefore a separate entry point (a mix task, e.g. `mix nonprofiteer.bootstrap`), run once against a live node. Two stages, mirroring the data model's spine-then-detail shape:
  1. **BMF bulk seed** — download the EO BMF extract(s), upsert `organizations`. Fast (CSV, MB-scale), no XML. Establishes the spine so detail has something to attach to. **In practice the BMF is full-universe every monthly drop, so `BmfCoordinatorWorker`'s normal cron path already seeds from empty — BMF needs no separate bootstrap task.** The cold-start/steady-state split matters for the *XML* pass (backfill ~3 years once, then incremental), not the spine.
  2. **990 XML detail pass** — parse Part VII → `people`/addresses, link to the org spine. Slower; enqueue through Oban so it's paced, durable, and resumable, rather than run inline.
- Bulk and detail **upsert on the same identity** (per resource's upsert action, keyed on the source's stable key — *not* EIN, per D7). So the detail pass merges cleanly over the bulk seed, filling fields the BMF doesn't carry. Run order never corrupts; re-runs converge.

## Pin the column layout — fail loud on drift

The single biggest risk (per [TODO.md](../../../docs/TODO.md)) is **silent** parse failure from schema drift. Guard it structurally:

- The BMF CSV parser **asserts its expected column layout** before mapping rows — if a column is added/removed/reordered upstream, the ingest raises rather than quietly writing garbage into the wrong fields.
- Same principle for Part VII XML: drive the parse from the **NODC concordance**, and validate output against **IRSx** as the reference. A parse that produces zero people for a filing that clearly has officers is a red flag, not an empty success.
- Never treat "the job finished without raising" as "the data is correct." Known-answer fixtures (below) are the real check.

## Idempotency & orphans

- Every ingest step is **safe to re-run** — monthly cadence + Oban retries mean the same extract/return gets processed repeatedly. Idempotent upserts (Ash create actions with `upsert? true`) make re-runs converge instead of duplicating.
- **Orphans** — a Part VII person (or later, a Schedule I grant) whose org isn't in the spine yet. Don't let an orphan fail the batch or get silently dropped: count orphan skips, log them on the run row (see below), and reconcile on a later pass once the spine catches up. In the bulk path this falls out of a merge join (rows with no matching master are dropped, counted, not persisted); in the incremental path, decide explicitly whether to defer or provisionally create the missing parent.

## Huge files: stage via COPY, don't load into memory

For the multi-GB inputs (Phase 2 financial schedules; large XML batches), don't per-row upsert and don't read the whole file into memory:

- Stream the file through Postgres `COPY` into a **temp staging table**, then `INSERT … ON CONFLICT (key) DO UPDATE` into the real table. The file never materializes in the BEAM heap, and the conflict clause keeps idempotency.
- Merge-join against the master table in the same statement so orphans are dropped by the join, not by loading-then-filtering in Elixir.

## Run logging (observability)

- Every ingest unit (per BMF extract, per parse batch) writes a **durable run row** on both success *and* failure — Oban's job table tracks process exit, not "did this actually ingest correct data." Record source, bucket/extract id, row counts, and `orphan_skipped_count` (defaulting to 0 so clean runs read clean). Build this run-log resource early; it's the audit trail behind the D8 provenance guarantee and the drift guard.

## Known-answer fixtures (catch drift before prod does)

Adapted from ohfec's `fetch_examples` — a task that captures **real source samples** into committed fixtures:

- Pull a curated set of real BMF rows + real 990 XML filings → `test/fixtures/bmf/*.csv`, `test/fixtures/990/*.xml`. These double as (a) HTTP stub bodies for worker tests (see `oban` skill) and (b) **known-answer fixtures**: parse them, assert the exact expected orgs/people/addresses come out.
- Re-run the capture periodically and **diff** — that's how column-layout or schema drift gets caught deliberately, instead of only surfacing when a production job breaks.
- **Source-of-truth precedence:** a captured real-response fixture always beats a published schema/spec. Specs drift from what the source actually emits; the fixture is ground truth. Validate the parser against IRSx, but pin the fixtures to real IRS files.

## ToS-sensitive data is opt-in

Financial schedules and any resale-sensitive slices (Phase 2, pending the licensing/ToS review in DECISIONS) stay **behind an explicit flag**, never in the default ingest path — mirroring how ohfec gates its contributor-level Tier 3 backfill. Don't wire Phase 2 schedules into the monthly cron until that review clears.

## Big-schema slicing (context hygiene)

When working against a large source schema (the NODC concordance, a big XML schema), prefer a small task that prints **one definition** over loading the whole thing into context — ohfec does this with `mix oh_fec.swagger_def` against its 868KB spec. Worth building the equivalent if/when the concordance proves unwieldy to read whole.
