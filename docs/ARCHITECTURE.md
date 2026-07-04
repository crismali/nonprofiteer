# Nonprofiteer — Architecture

Status: **draft.** High-level design reflecting the decisions in
[DECISIONS.md](DECISIONS.md). Detailed schema and API contracts get their own docs as the
design firms up.

## Stack

- **Language/runtime:** Elixir.
- **Web/API:** Phoenix (thin LiveView UI later; JSON API + sync feed via Phoenix or an
  Ash-generated API layer).
- **Domain/data layer:** **Ash Framework** over Ecto/PostgreSQL. Ash resources model the
  domain; can generate REST/GraphQL and admin tooling from the same definitions.
- **Datastore:** PostgreSQL, full-text/fuzzy search via `tsvector` / `pg_trgm`.
- **Ingestion:** Elixir pipeline with Oban for durable, scheduled background jobs. Cross-
  version XML parsing driven by the **NODC concordance**, validated against **IRSx** (see
  [DATA-SOURCES.md](DATA-SOURCES.md)).

Same stack as the sibling **ohfec** project, so patterns and conventions carry across.

## The two boundaries that define this system

1. **Nonprofiteer is a use-agnostic 990 source of truth.** It models 990 data faithfully
   (orgs, filings, people, addresses, financial line items) and exposes it. It knows
   **nothing** about ohfec, contact-matching, coordination, or campaign finance. No
   consumer vocabulary in the schema.
2. **Consumers sync, they don't proxy.** Nonprofiteer exposes a generic, per-resource
   **changed-since** feed. A consumer (ohfec first) pulls a bulk snapshot, then monthly
   incrementals, into its *own* resources — the same cache-not-proxy pattern ohfec already
   uses for OpenFEC. This gives consumers data locality (e.g. `pg_trgm` joins) without
   Nonprofiteer needing to know why.

These are why we are **not** building a per-request HTTP API as the ohfec bridge, and why
no ohfec-shaped projection (`ContactRecord` tuples, match scores) lives here. ohfec builds
that on its side.

## System shape

```
        ┌──────────────────────── Data Sources ─────────────────────────┐
        │  IRS EO BMF (CSV)   GivingTuesday Data Lake (990 XML + index)  │
        │                     ProPublica API (prototype/validation)     │
        └───────────────┬───────────────────────────┬───────────────────┘
                        │                           │
                 ┌──────▼───────┐            ┌──────▼────────────┐
                 │  BMF ingest  │            │  XML ingest       │   (Oban)
                 │  (registry)  │            │  Phase 1: Part VII│
                 │              │            │  Phase 2: full    │
                 └──────┬───────┘            └──────┬────────────┘
                        │      NODC concordance     │
                        └──────────┬────────────────┘
                                   ▼
                        ┌─────────────────────┐
                        │   PostgreSQL        │
                        │   (Ash resources)   │
                        │ Org / Filing /      │
                        │ Person / Address    │
                        └──────────┬──────────┘
                                   │
                 ┌─────────────────┼───────────────────┐
                 ▼                 ▼                   ▼
         ┌──────────────┐  ┌───────────────┐   ┌──────────────┐
         │ changed-since│  │  JSON API     │   │ thin LiveView│
         │  sync feed   │  │  (public,     │   │  UI (later)  │
         │  (Phase 1)   │  │   later)      │   │              │
         └──────┬───────┘  └───────────────┘   └──────────────┘
                │ bulk + monthly incrementals
                ▼
        ┌────────────────────────────────────────────┐
        │ ohfec: syncs into its OWN resources, runs   │
        │ entity resolution / contact-matching /      │
        │ scoring. Owns all judgment.                 │
        └────────────────────────────────────────────┘
```

## Data model (sketch — see future DATA-MODEL.md)

- **Organization** — **surrogate primary id** (stable, Nonprofiteer-owned). **EIN is an
  indexed attribute, cardinality 0/1/many** — *not* the primary key. This absorbs the
  messy cases: reorganizations that issue a new EIN, orgs with multiple EINs, and
  especially **group exemptions**, where one central EIN covers many subordinate orgs.
  Model **central-vs-subordinate explicitly** (a subordinate points at its central org);
  do not assume EIN uniquely identifies an org.
- **Filing** — one per submitted return (990/990-EZ/990-PF) per year. Links to Org.
  Filing metadata + source-filing pointer for provenance.
- **Person** — officers, directors, trustees, key/highest-comp employees from **Part VII**:
  name, role/title, and associated address. (Compensation/tenure = Phase 2.) Every emitted
  person record carries enough to be *matchable elsewhere* — but Nonprofiteer does no
  matching itself.
- **Address** — normalized; attached to orgs and (via Part VII) people.
- **Financial line items** — Phase 2.

**Guarantee for consumers:** every emitted Org/Person record ships with an **address and
(where the org has one) an EIN**, plus a source-filing pointer — so a downstream matcher
always has a corroborating field and can trace any claim to the public record. This is a
data-quality guarantee, not a matching feature.

## Data flow

1. **BMF ingest** (monthly): download EO BMF → upsert `organizations` (identity, address,
   NTEE, central/subordinate structure). Establishes the spine.
2. **XML ingest** (monthly, incremental via Data Lake index files):
   - **Phase 1:** parse **Part VII only** → `people` + addresses, link to Org.
   - **Phase 2:** parse remaining schedules → financials, then Schedule I/R.
   - Preserve a source-filing pointer on everything.
3. **Serve:** the **changed-since sync feed** (Phase 1 priority), plus the public JSON API
   and thin UI (later).

Incrementality rides the Data Lake **index files** — track what's ingested, process only
new/changed returns.

## Sync feed (the Phase-1 deliverable)

- Generic and per-resource — a consumer asks "what Orgs/People changed since `<cursor>`?"
- **Cadence:** monthly (matches IRS batch drops). No streaming.
- **Cursor:** IRS release month vs. monotonic `updated_at` — **open**, see below.
- Bulk snapshot for first sync, then incrementals.
- Must define **amendment and delete** semantics (an amended return supersedes a prior
  one; how does that surface to a consumer that already synced the old row?).

## API design (public, later)

- Versioned (`/api/v1/...`), read-only, tiered for rate/volume (affordability model).
- Org lookup by EIN/id, org search (name/NTEE/location), org detail + filing history,
  filing detail, people search. JSON, paginated, source-filing references included.

## Campaign-finance integration (ohfec)

The bridge is the **sync feed above**, consumed into ohfec's own resources. On ohfec's
side (not ours): map synced Orgs/People/Addresses into its `EntityResolution` /
`ContactRecord` / `SharedContacts` layer.

- **Primary signal:** shared **people** and **addresses** between nonprofits and FEC
  committees (a nonprofit officer ≈ a committee treasurer). ohfec's dormant `:exact` EIN
  tier lights up once these EIN-bearing records arrive; matching otherwise rests on
  name + address, with EIN as strong corroboration.
- **Secondary signal:** org-to-org money (Schedule I/R), Phase 2.
- **All confidence/scoring/assertions live in ohfec** — Nonprofiteer ships facts only.

## Validation

Data-pipeline validation = **known-answer checks**, not green tests:

- **Coverage/quality metrics:** % of orgs with a parsed Part VII; null rates on
  name/address/EIN; dedupe/amendment correctness.
- **Known-answer fixtures:** real nonprofit↔committee pairs sharing an officer/address,
  verified to surface end-to-end in ohfec. **None exist yet — must be built early**
  (borrow candidates from ohfec's `docs/EXAMPLES.md`). They double as the schema-drift
  regression guard: Part VII parse bugs fail *silently*, so without fixtures you can't
  distinguish "working" from "silently dropping half the officers."

## Deployment (early thoughts)

- Single Phoenix app (API/sync/UI) + Postgres + Oban workers. One BEAM deployment.
- Bulk XML corpus storage cost is the main variable — see
  [DATA-SOURCES.md](DATA-SOURCES.md).

## Open questions

- Ash-generated API (AshJsonApi/AshGraphql) vs. hand-rolled Phoenix JSON.
- In-BEAM XML parsing vs. a separate service reusing IRSx directly.
- Sync cursor semantics + amendment/delete handling.
- Postgres FTS vs. dedicated search as coverage grows.
- Backfill depth (cost/volume tradeoff).
