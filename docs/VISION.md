# Nonprofiteer — Vision

## The problem

The IRS publishes a huge amount of data about tax-exempt organizations: registration
records, annual Form 990 filings, financials, board members, key employee compensation,
grants made, and more. This data is public and free — but it is not *usable*. It ships as
raw XML e-file returns, fixed-width and CSV master files, and PDFs. Making sense of it
requires parsing versioned schemas, reconciling organizations across datasets, and
normalizing years of inconsistent filings.

The tools that *have* done this work — GuideStar / Candid being the dominant one — sit
behind expensive paywalls. Detailed financials, historical filings, and bulk/API access
are priced for institutions, not for journalists, small researchers, community
organizers, or civic developers.

## What we're building

**Nonprofiteer** turns raw public 990 data into a clean, normalized dataset with a
browsable resource and an API on top — an affordable, open alternative to GuideStar.

It is deliberately a **use-agnostic source of truth**: it models 990 data faithfully and
exposes it, and knows nothing about how any particular consumer wants to use it. (See
[Near-term reality](#near-term-reality-infrastructure-first) — the first consumer is our
own campaign-finance project, but that consumer's concepts must never leak into
Nonprofiteer's schema.)

Two surfaces, one dataset:

1. **Browsable web resource** — search and browse organizations, view normalized
   financial timelines, officers/directors, and links to source filings. *(Later. Thin
   until there's an external audience.)*
2. **API / sync feed** — programmatic access to the same normalized data, with a generic
   incremental **changed-since** sync so consumers can maintain a local copy. *(First.)*

## Near-term reality: infrastructure-first

Honestly stated: for the next several months this is **infrastructure**, not a consumer
product. The public GuideStar-alt is a real goal, but later. The near-term goal is to
feed one consumer — the sibling **ohfec** campaign-finance project — with clean nonprofit
data. That means: invest in the data layer, parsing, and sync feed; keep the UI thin;
defer pricing/auth/consumer polish.

### Why ohfec needs this, concretely

**ohfec** (`~/Development/public-data-projects/ohfec`, sibling dir) is a Phoenix/Ash app over the OpenFEC API.
OpenFEC is federal-only and structurally blind to 501(c)(4)/(c)(3) nonprofits — the
classic dark-money vehicles — because they don't file with the FEC at all. Money and
influence trails dead-end at these orgs.

Nonprofiteer's 990 data reopens those trails. The **primary** signal is **shared people
and shared addresses**: if a Super PAC and a nonprofit share an officer, or list the same
address, they're likely less independent than they appear. This maps directly onto ohfec's
existing `ContactRecord` / `SharedContacts` contact-matching — a nonprofit officer is the
analog of a committee treasurer. A **secondary** signal is org-to-org money (990
Schedule I grants-out, Schedule R related-orgs). ohfec even has a dormant EIN-matching
tier already built, waiting for an EIN-bearing source like this one.

**Division of labor:** Nonprofiteer provides clean, normalized *facts* (names, addresses,
EINs, roles, source-filing pointers). ohfec owns all *judgment* — entity resolution,
match confidence, and any "these two are connected" assertion. Nonprofiteer never asserts
a match.

## Who it's for (eventually)

- **Journalists & researchers** investigating a nonprofit's finances or people.
- **Civic developers** who need nonprofit data as an input (ohfec is the first).
- **Small orgs & grantmakers** who can't justify a GuideStar/Candid subscription.

## Positioning vs. GuideStar / Candid

| | GuideStar / Candid | Nonprofiteer |
|---|---|---|
| Price | Enterprise paywall | Affordable / open |
| API | Gated, costly | First-class, cheap |
| Data | Curated + proprietary enrichment | Public IRS data, normalized transparently |
| Audience | Institutions | Journalists, devs, small orgs |

We are **not** trying to out-curate Candid's proprietary enrichment. Our edge is
**transparent, affordable access to the public record**.

## Guiding principles

- **Use-agnostic source of truth.** No consumer's vocabulary leaks into the schema.
- **Public data stays legible.** Every normalized value traces back to a source filing.
- **Facts, not judgments.** We provide data; consumers assert relationships.
- **Sync-first.** Consumers maintain a local copy via a generic changed-since feed.
- **Affordable by design.** Low marginal cost so pricing can stay low.
- **Ingest is a pipeline, not a one-off.** New filings land monthly; built to keep absorbing.

## Non-goals (for now)

- Proprietary data enrichment or scoring/ratings.
- Asserting relationships/coordination between entities (that's a consumer's job).
- Non-US nonprofits.
- Real-time filing (IRS data lags 1–2 years).
- A consumer-grade UI before there's an external audience.

## Open questions

- **Data source strategy** — see [DATA-SOURCES.md](DATA-SOURCES.md).
- **Monetization** — free tier + paid API tiers? Deferred.
- **Backfill depth** — how many years of history up front vs. going-forward only.
