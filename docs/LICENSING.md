# LICENSING.md — data sources, terms, and posture

Where Nonprofiteer's data comes from, what each source's terms actually permit, and the license
posture that follows. Terms were read from the sources' own pages (see links); **this is not
legal advice** — confirm with counsel before charging for access, especially the ODbL
"derivative database" question below.

## Source-by-source

### IRS EO Business Master File — public domain (clean)

Pulled from irs.gov directly (`https://www.irs.gov/pub/irs-soi/eo_*.csv`). US federal government
works carry no copyright (17 U.S.C. § 105), and the BMF exists precisely to be public. Freely
usable, redistributable, and **commercializable** with no conditions. This is the org spine.

### IRS 990 e-file XML — public-domain content, accessed via an ODbL host

The **content** of the 990 XML is IRS public-domain record — a license can't re-copyright public
facts. But we currently *access* it through the **GivingTuesday 990 Data Lake**
(`gt990datalake-rawdata`), whose **index files + curation are licensed
[ODbL](http://opendatacommons.org/licenses/odbl/1.0/) + DbCL**:

- **Attribution** required.
- **Share-alike** — a derivative *database* must also be ODbL.
- Changes to the database structure must be documented.

The distinction that matters: ODbL governs *their compilation* (the index that says which filings
exist), **not** the public-domain XML we extract and serve. Our exposure is the discovery/index
layer, not the returns themselves.

### ProPublica Nonprofit Explorer — excluded from the product

ProPublica's [Data Store terms](https://projects.propublica.org/datastore/terms/) are
incompatible with our model: *"can't charge people money to look at the data,"* *"can't republish
… or otherwise distribute,"* *"can't resell or sub-license."* Therefore **ProPublica is never in
the ingest pipeline or the served data** — the codebase has zero references to it, and it stays
that way. At most it's a manual, dev-time cross-check by a human; nothing it returns is persisted
or served.

## The posture: ODbL-compatible because we're open

ODbL looks like a problem for "resale," but it's compatible with Nonprofiteer's positioning as an
**open** alternative to GuideStar (see [VISION.md](VISION.md)). ODbL **permits commercial use and
charging for access**; it only requires the database stay **open** (share-alike) and **attributed**.
So:

- **License Nonprofiteer's own dataset ODbL**, attribute IRS + GivingTuesday, and charge for
  hosted API tiers / convenience — exactly what GuideStar/Candid do over the *same* public data.
  Share-alike is satisfied because we're open anyway.
- The affordability thesis is sound: **you can't own public records.** The charge is for
  access and infrastructure, not the facts.

**Attribution to ship** (on the API/feed and in a `NOTICE`): source data from the **IRS** (public
domain) and, for the 990 e-file corpus, the **GivingTuesday 990 Data Infrastructure Project**
(ODbL). 

**For counsel before a paid launch:** does index-driven ingestion make our *entire* database an
ODbL "derivative database" (share-alike on everything), or does it only require attribution? If we
ever want a proprietary layer, the exit path below sidesteps the question.

## Compliance guardrail: never ingest non-public 990 data

Independent of licensing — a legal line. Part VII officer names/titles and the org business
address **are** public disclosure (Phase 1 is clean). But:

- **Schedule B (donor names/addresses) is NOT public** — never ingest or serve it.
- **SSNs / other PII** must never appear in stored or served data.
- When Phase 2 adds schedules, treat this as a **hard allowlist** of public fields, not a
  denylist.

## Exit path: removing the GivingTuesday dependency

Optional — the *availability* risk is already handled (D11: we mirror every source XML to our own
object storage). Removing GivingTuesday entirely means sourcing 990 XML from IRS directly:

- IRS publishes XML as **monthly ZIP archives** (`apps.irs.gov/pub/epostcard/990/xml/{YEAR}/{YEAR}_TEOS_XML_{MM}{A..}.zip`)
  plus a per-year `index_{YEAR}.csv` — not individual per-filing files.
- **Effort ≈ 2–3 days, concentrated in the fetch layer.** Unchanged: `Efile.PartVii` (the
  drift-prone parser), the data model, the R2 mirror, the sync feed, supersede — the XML content
  is identical. Changed: remap `Efile.Index` to the IRS index columns + point `EfileIndexWorker`
  at IRS per-year index URLs (~½–1 day), and add a ZIP-ingestion worker that stream-unzips a
  monthly archive and processes/fans-out per XML with month-level incrementality (~1–2 days; must
  stream, the ZIPs are large for a small VPS).

Not needed unless we choose to go proprietary or drop the single-third-party discovery source.
