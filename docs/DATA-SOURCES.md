# Nonprofiteer — 990 Data Sources

Status: **strategy set; some specifics open.** This doc weighs the candidate sources and
records the ingestion strategy.

## The candidates

### 1. IRS EO Business Master File (EO BMF) — the org spine

The IRS registry of every org with a tax-exempt determination.

- **Where:** IRS.gov EO BMF extract; also republished cleaned by NCCS / Urban Institute.
- **Format:** CSV, one row per EIN, split by state + DC + PR + international. Name, EIN,
  address, NTEE code (activity classification), ruling date, deductibility, asset/income
  codes.
- **Role:** the canonical list of *which orgs exist* and how they're categorized. Small,
  easy to ingest, no XML. Gives us org coverage even for orgs that haven't e-filed.
- **Limit:** registry only — **no financial detail, no filing history, no people.** A
  complement to the 990s, not a substitute.

### 2. IRS 990 e-file XML (bulk) — the deep data

Electronically-filed 990/990-EZ/990-PF returns as structured XML (post-2011,
electronic-only). This is the richest source — it *is* the filing: officers (Part VII),
financials, schedules, grants.

- **Where:** the original IRS→AWS S3 dataset was **frozen 2021-12-31**. Live options now:
  - **GivingTuesday Data Lake** (S3) — maintains the full-universe e-file 990 XML corpus
    plus clean index files. What the active tooling (`irs990efile`) pulls from.
  - **IRS.gov Form 990 series downloads** — official XML, by year and month.
- **The hard part — versioned schemas.** The IRS revises the XML schema **annually**;
  field locations drift across dozens of versions since 2011. Cross-version mapping is the
  core engineering problem. **Do not hand-roll it** — reuse:
  - **NODC concordance** (Nonprofit Open Data Collective) — the variable-to-version
    mapping published as data; drive an Elixir parser from it.
  - **IRSx** (`jsfenfen/990-xml-reader`, Python) — mature parser; use as a **reference
    validator** for our output.
- **Pros:** complete data, no rate limits (bulk files), we own the pipeline end to end.
- **Cons:** most engineering; large volume; must dedupe amended returns.

### 3. ProPublica Nonprofit Explorer API (v2) — accelerator, not backbone

Pre-parsed 990 data + org search as JSON.

- **Where:** `https://projects.propublica.org/nonprofits/api`
- **Pros:** fastest to a working prototype (parsing already done); great as a cross-check.
- **Cons:** external dependency for a **core** dataset — unacceptable as a foundation for a
  product whose value is owning affordable access. Bound by ProPublica's ToS; rate limits
  unpublished. Use for prototyping/validation only, never as the backbone.

## How they relate

Three **layers**, not three alternatives:

- **BMF** → *what orgs exist and how they're classified.* Browse/search spine.
- **e-file XML** → *their people, addresses, finances, filing history.* The deep data.
- **ProPublica API** → *someone already parsed it.* Prototype accelerator + reference check.

## Ingestion strategy & phasing

**Phase 1 — the ohfec-useful slice, minimum schema surface:**

- **BMF ingest** → `organizations` (identity, address, NTEE). No XML.
- **990 Part VII parse only** → officers/directors/key employees (names, roles) + their
  associated addresses. Part VII is a small, targeted slice of the XML — **all financial
  schedules are deferred.** This is exactly what ohfec's people/address matching needs, and
  it dodges most of the schema surface.
- Parse via the **NODC concordance**; validate against **IRSx**.
- Ship over the generic **changed-since sync feed** (see
  [ARCHITECTURE.md](ARCHITECTURE.md)).

**Phase 2 — full 990 depth:**

- Parse the remaining schedules: full financials, then **Schedule I (grants out)** and
  **Schedule R (related orgs)** for the org-to-org money signal.
- Replace any ProPublica-sourced data with our own parse.

**Phase 3 — public product:** enrichment, the browsable UI, API tiers. Supplementary
sources beyond the 990 (990-N, auto-revocation, state charity registries, USASpending,
etc.) are cataloged in [FUTURE-SOURCES.md](FUTURE-SOURCES.md).

> **Signal priority note:** an earlier draft over-indexed on Schedule I/R money. The
> **primary** value for ohfec is **people + address overlap** (Part VII + org header),
> which is why it's Phase 1 and money is Phase 2. Money corroborates; shared people/
> addresses are the cheaper, stronger lead.

## Recommendation summary

Own the pipeline. BMF for breadth on day one; e-file XML (via GivingTuesday Data Lake,
parsed through the NODC concordance) for the depth that justifies the product; ProPublica
only to de-risk the early build. Never let the core depend on someone else's API.

## Open questions

- **Cadence/cursor:** IRS drops XML + BMF **monthly**, so sync is a monthly incremental
  pull. Cursor = IRS release month vs. a monotonic `updated_at`? Amendment/delete handling?
- **Provenance storage:** decided — mirror source XML into our own object storage (see
  [DECISIONS.md](DECISIONS.md) D11).
- **Backfill depth:** decided — ~3 filing years up front + going-forward (see
  [DECISIONS.md](DECISIONS.md) D9).
- **Licensing/ToS:** reviewed — see [LICENSING.md](LICENSING.md) + [DECISIONS.md](DECISIONS.md)
  D18. IRS data is public domain; the Data Lake is ODbL (compatible with our open posture);
  ProPublica is excluded from the pipeline. Counsel sign-off still needed before a paid launch.
- **Validation fixtures:** none yet — must find/build known-answer cases (see
  [ARCHITECTURE.md](ARCHITECTURE.md) validation).

## Sources

- [IRS 990 Filings — Registry of Open Data on AWS](https://registry.opendata.aws/irs990/)
- [IRS Form 990 series downloads](https://www.irs.gov/charities-non-profits/form-990-series-downloads)
- [irs990efile (GivingTuesday Data Lake tooling)](https://github.com/Nonprofit-Open-Data-Collective/irs990efile)
- [IRSx / 990-xml-reader](https://github.com/jsfenfen/990-xml-reader)
- [ProPublica Nonprofit Explorer API v2](https://projects.propublica.org/nonprofits/api)
- [IRS EO Business Master File Extract](https://www.irs.gov/charities-non-profits/exempt-organizations-business-master-file-extract-eo-bmf)
- [NCCS Business Master File](https://urbaninstitute.github.io/nccs/datasets/bmf/)
