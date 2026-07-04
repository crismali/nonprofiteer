# Nonprofiteer — Decisions

Locked decisions with their reasoning, so they aren't relitigated or silently reversed.
Newest concerns at the bottom. Terse by design; the "why" is the point.

## D1 — Infrastructure-first, not consumer product (yet)

Near-term goal is feeding the sibling **ohfec** campaign-finance project, not launching a
public GuideStar alternative. Invest in data layer + parsing + sync feed; keep the UI
thin; defer pricing/auth/consumer polish. The public product is real but later.

## D2 — Use-agnostic source of truth

Nonprofiteer models 990 data faithfully and exposes it, and knows **nothing** about how
consumers use it. No ohfec/campaign-finance/contact-matching vocabulary in the schema.
**Why:** coupling a would-be public product to one consumer's internals is the trap; keep
the boundary clean now while it's cheap.

## D3 — Sync feed, not per-request API, for the ohfec bridge

Expose a generic per-resource **changed-since** feed; consumers pull a bulk snapshot then
monthly incrementals into their *own* resources (cache-not-proxy, exactly how ohfec treats
OpenFEC). **Why:** ohfec's matching needs data locality (`pg_trgm` joins across both
datasets); a per-name remote HTTP call is the slow, wrong path. Monthly cadence because
IRS drops 990 XML + BMF monthly and filings lag 1–2 years — no streaming needed. The
public HTTP API is a later, separate deliverable for external users.

## D4 — Facts, not judgments

Nonprofiteer ships raw signals (name, address, EIN, role, source-filing pointer) and
**never asserts a match** or coordination. Consumers own entity resolution, confidence
scoring, and any "these two are connected" claim. **Why:** matching named individuals to
imply "not independent" is defamation-shaped; that judgment belongs in one place, with
full context, governed by that consumer's ethics discipline (ohfec's `/disclaimers` rule).

## D5 — Primary signal is people + address, money is secondary

The Phase-1 target is **shared people and addresses** (990 Part VII + org header), which
maps onto ohfec's existing `ContactRecord`/`SharedContacts` matching (a nonprofit officer
≈ a committee treasurer). Org-to-org money (Schedule I/R) is a secondary Phase-2 signal.
**Why:** shared people/addresses is the cheaper, stronger lead; an earlier draft
over-indexed on money-flow.

## D6 — Phase 1 = BMF + Part VII only; reuse the parser

Phase 1 ingests the **BMF** (org identity, no XML) plus **990 Part VII only**
(people/addresses), deferring all financial schedules. Cross-version XML parsing is driven
by the **NODC concordance**, validated against **IRSx**. **Why:** Part VII + BMF is a
fraction of the schema surface and is exactly what ohfec needs; the annual schema-version
drift is the biggest time sink and is already solved as reusable data — don't re-derive it.

## D7 — Surrogate primary ID; EIN is an attribute (0/1/many)

Organizations get a stable Nonprofiteer-owned surrogate id. **EIN is an indexed attribute,
not the primary key**, and may be absent, single, or repeated. Model **central-vs-
subordinate** orgs explicitly (group exemptions put many orgs under one central EIN).
**Why:** this is the one decision genuinely expensive to reverse once a consumer syncs
against the identifier. EIN is ~95% clean — reorganizations, multi-EIN orgs, and
especially group-exemption subordinates break "EIN = org." Subchapters sharing an EIN has
caused real pain on past projects; the surrogate absorbs it without a breaking migration.

## D8 — Corroboration guarantee

Every emitted Org/Person record ships with an **address and (where the org has one) an
EIN**, plus a source-filing pointer. **Why:** guarantees a downstream matcher always has a
corroborating field so a match is never name-only, and every value traces back to the
public record. A data-quality guarantee, not a matching feature.

## D9 — Backfill ~3 filing years, then going-forward

Phase 1 ingests roughly the **last 3 filing years** plus all new filings going forward;
deepen history later if needed. **Why:** covers the current + prior election cycle (what
ohfec cares about), keeps Phase-1 volume/storage modest, and history can be backfilled
incrementally without a redesign. Note the 1–2 year filing lag means "3 filing years" is
already several calendar years of tax-year coverage.

## D10 — Never destroy history (amendments + deletes)

An **amended** 990 does **not** overwrite the prior filing: keep both, mark the old one
superseded with a `superseded_by` pointer, and surface both over the changed-since feed. A
**deleted/withdrawn** filing is **soft-deleted** (tombstone in the feed), never
hard-deleted. **Why:** the *history* is signal, not noise — a restatement or a vanished
filing can indicate unethical behavior, and consumers (ohfec already tracks FEC
amendments) want to see it. A consumer that hard-deletes on its side can, but Nonprofiteer
never forces the loss. Costs a status flag + supersedes pointer.

Consequence: the sync cursor must emit supersede/tombstone events, not just upserts — so a
consumer syncing incrementally learns a row changed status, not only that new rows exist.

## D11 — Mirror source XML ourselves

As we ingest, copy each source 990 XML into our own object storage (not just a pointer to
the Data Lake). Costs storage. **Why:** full reproducibility and "trace to the exact
source" must always work — and the source can vanish (the original IRS→AWS bucket already
froze in 2021; the GivingTuesday Data Lake is a single third party). Given D10 (history is
sacred), depending on someone else's read-time availability for our provenance would
undercut the whole stance. Storage is cheap relative to that risk.

## Open (not yet decided)

- Sync cursor mechanism (IRS release month vs. `updated_at`) — the *what-changed* query;
  D10 settles that supersede/tombstone events must be emitted. (Build-time detail.)
- Validation fixtures — to be developed (known-answer nonprofit↔committee cases).
- Licensing/ToS review (GivingTuesday Data Lake, ProPublica) before any resale — my task.
- Build-time technical: Ash-generated vs hand-rolled API; in-BEAM parse vs separate IRSx
  service.
