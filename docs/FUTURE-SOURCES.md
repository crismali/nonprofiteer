# Nonprofiteer — Future / Supplementary Data Sources

Status: **catalog, not committed.** Sources beyond the core 990 pipeline
([DATA-SOURCES.md](DATA-SOURCES.md)) that could enrich the nonprofit picture. Each is its
own ingest + Ash resources + sync tier when built. **Decide per-source licensing / ToS /
PII before ingesting** — same discipline the sibling ohfec project applies.

Framing: the core pipeline models a nonprofit's **990 filings**. These sources either
**complete the IRS exempt-org picture** (coverage/accountability gaps the 990 XML alone
misses) or **enrich** an org with activity/context from adjacent public data. Nonprofiteer
stays a **use-agnostic source of truth** — it ingests facts; consumers (ohfec, etc.) decide
what they mean. See [DECISIONS.md](DECISIONS.md) D2/D4.

## Core — completes the IRS exempt-org picture (arguably Phase 2, not mission creep)

- **Form 990-N (e-Postcard)** — orgs under ~$50k gross receipts file 990-N, **not** the full
  990, so the e-file XML pipeline misses them entirely. Ingesting 990-N closes a large
  coverage hole (a big share of all exempt orgs by count). Access: IRS publishes 990-N
  data as a downloadable dataset. Low lift, high coverage payoff.
- **IRS Auto-Revocation List** — orgs whose exempt status was automatically revoked for
  failing to file for three consecutive years. A live **accountability signal** (aligns
  with D10 — a status change / lapse is itself signal, not noise). Access: IRS bulk
  download. Cheap.
- **IRS Pub 78 / Tax Exempt Organization Search (TEOS) bulk** — deductibility status +
  determination data; complements the BMF spine. Access: IRS bulk files. Cheap.
- **NCCS / Urban Institute core files** — cleaned, harmonized nonprofit datasets (already
  the BMF republisher we lean on). Reduces normalization burden and doubles as a
  validation reference against our own parse. Reference/enrichment.

## Enrichment — adjacent public data (genuine scope expansion; flag before committing)

- **State charity registrations** — many states require charities to register and publish
  officers, addresses, and financials (e.g. NY AG Charities Bureau, CA Registry of
  Charitable Trusts). Charity-specific, sometimes richer/earlier than federal data. Access:
  per-state, fragmented (some open-data portals, some scraping). Overlaps *business
  registries* below but higher-signal for nonprofits.
- **Business entity registries (registered agents / officers)** — nonprofits are
  state-incorporated entities with articles, registered agents, and officers — another
  view of the same people/address data the 990 Part VII carries, useful for corroboration.
  Access is the catch: OpenCorporates (bulk licensing) or 50 fragmented Secretary-of-State
  sites. *(Also on ohfec's list, for shell-company detection.)*
- **USASpending.gov (federal grants)** — nonprofits are major federal grant recipients; an
  org's award history is real "who funds it" enrichment. Join: recipient name + address
  (fuzzy), or via SAM.gov identifiers. Access: robust free API + bulk. *(ohfec lists it for
  contractor-donor detection — different lens, same source.)*
- **SAM.gov entity registrations** — entities registered for federal awards: addresses +
  points-of-contact, and the identifier bridge (UEI) to USASpending. Access: public entity
  API/extract. **Caveat:** EIN/TIN is frequently withheld from the public extract, so
  EIN-join is partial — verify current field availability before relying on it.
- **Lobbying disclosure (LDA)** — 501(c)(4)/(c)(6) orgs lobby and hire lobbyists; LDA
  registrants/clients include nonprofits → an influence/activity layer on an org profile.
  Access: Senate Office of Public Records bulk XML/API. *(Also on ohfec's list.)*
- **Sector regulators** — vertical-specific depth: nonprofit hospitals file **990
  Schedule H** + CMS cost reports; nonprofit universities → IPEDS. Niche but deep for those
  sectors.

## Lower priority / derived

- **OpenSecrets (CRP)** — pre-built 501(c) dark-money analysis + org parent-mapping. Derived
  (not primary source) + licensing/attribution caveat. A shortcut, not a foundation.
- **CourtListener (Free Law Project)** — nonprofit litigation/enforcement records. Free API.
  Marginal-to-medium.
- **GLEIF LEI** — some nonprofits carry a Legal Entity Identifier; free, global, but sparse
  coverage for US nonprofits. Marginal.

## Notes

- **Overlap with ohfec is expected and useful.** Where a source (business registries,
  USASpending, lobbying) appears in both projects, nonprofiteer ingests the
  *nonprofit-org* view and ohfec ingests the *campaign-finance* view; they meet at the
  entity-resolution boundary, not by sharing an ingest.
- **Coverage vs. mission creep.** 990-N and Auto-Revocation complete the exempt-org record
  we already claim to cover — treat as Phase-2 core. SAM / state-charity / lobbying /
  USASpending broaden the mission — treat as opt-in enrichment, decided one at a time.
- **Provenance still applies** — anything ingested follows D8 (address+source pointer) and
  D11 (mirror the source) so every value traces back to its origin.
