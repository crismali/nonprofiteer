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

## D12 — BMF upserts on a partial `[:source, :ein]` identity, not global EIN

BMF ingest keys its idempotent upsert on the identity `:unique_bmf_ein` — EIN, but **only
where `source == :bmf`** (a partial unique index). A new `source` attribute (nullable atom,
`:bmf` today) records ingest provenance and scopes the constraint. **Why:** a BMF extract is
one row per EIN, so a monthly re-run needs a stable per-EIN upsert target or it duplicates
every org — yet D7 forbids making EIN globally unique (reissue, multi-EIN, group exemptions,
and future non-BMF sources all break "EIN = org"). Scoping uniqueness to BMF-sourced rows
gets idempotency for the one source where EIN *is* one-per-row, while EIN stays globally
0/1/many for everyone else. Orgs first seen via a later 990-XML path carry a null `source`
and are untouched by the constraint. The partial-index predicate is hand-mirrored in the
resource (`identity_wheres_to_sql`) — the Ash `where` and the SQL must stay in lockstep.

## D13 — BMF fan-out is per-state; capture AFFILIATION for the GEN reconcile

The BMF coordinator fans out over the IRS **per-state** extract files (50 states + DC +
Puerto Rico + international `xx` = 53), not the 3 coarse regional files, verified live against
irs.gov (2026-07). **Why:** finer fan-out means one bad state can't fail a whole region, and
each run's `extract_id` is a meaningful state code for the run log. Same universe either way;
the trade is 53 small monthly downloads vs. 5 large ones — cheap for the observability.

Linking group-exemption subordinates to their central org (`BmfReconcileWorker`) is driven by
`Organization.affiliation_code` (raw BMF AFFILIATION): a group's central (codes 6/8) and its
subordinates (9) share the same `gen`, so AFFILIATION is the only thing that tells them apart.
The reconcile is **global** — a central and its subordinates routinely sit in different state
files (American Legion posts nationwide under one Indiana central) — so it's a post-ingest
pass over the whole table (monthly cron, the day after the fan-out), not per-extract work. It
builds a `gen`→central map, streams subordinates and sets `central_org_id`, and counts
subordinates whose central isn't in the dataset rather than forcing a link.

## D14 — 990 XML is parsed in-BEAM (Saxy), not via a separate IRSx service

Part VII is extracted in Elixir with Saxy (`Efile.PartVii`); IRSx stays a **reference
validator** run offline, never in the pipeline. **Why:** Part VII is a narrow slice (officer
names/titles + the filer address), the returns are small (KB–low-MB, so `Saxy.SimpleForm`
suffices — streaming is a Phase-2-schedules concern), and a single BEAM matches the single-
node deployment stance. Owning the parse end to end beats operating a second Python runtime +
an IPC boundary for a slice this small. We take on schema-version handling, but D9 keeps us in
one stable modern schema (see D15). Resolves the "in-BEAM vs separate IRSx service" open item.

## D15 — Part VII scope: Form 990 + modern schema only; skip-and-count orphans; raw except EIN

The first cut of the e-file parse is deliberately narrow, failing **loud** rather than silent:

- **Form 990 only** (990-EZ/990-PF carry officers in different elements — a follow-up) and
  **modern schema (2013+)** — both matching D9's ~3-filing-year window. Out-of-scope returns
  raise `UnsupportedReturnError`, a counted skip, never a silent empty parse.
- **Orphans skip-and-count.** A return whose (canonical) EIN isn't in the BMF spine is logged
  and dropped, not force-created — any 990 e-filer is in the EO BMF, and monthly BMF closes
  the gap, so this avoids duplicate orgs that would need merging. (Chosen over provisional org
  creation.)
- **Raw except the EIN.** Names/addresses are stored verbatim — normalization for matching is
  the consumer's job (ohfec's `EntityResolution`), per D2/D4 "ships facts only." Only the EIN
  is canonicalized (`Ingest.Ein`, digits-only 9), because it's the identifier orgs are joined
  on. A per-person Part VII address doesn't exist in the XML, so a person's D8 address is the
  filer's business address from the return header.
- **Amendment supersede (D10) is deferred** — amendments land as distinct filings keyed on
  `source_object_id` (no data lost); the `superseded_by` links are a follow-up (see TODO).

## D16 — Sync cursor is monotonic `updated_at`, bounded by the last completed batch

The changed-since feed cursor is each resource's **`updated_at`**, keyset-paginated on
`(updated_at, id)`; a consumer asks "changes since `<cursor>`." **Why:** Ash `timestamps()`
already puts `updated_at` on every resource and bumps it on every write, so it's free,
row-level resumable, and — because supersede and tombstone are *updates* — those status
changes (D10) surface **automatically**, no separate event log or per-writer bookkeeping. The
alternative (an IRS-release-month/batch cursor) is coarse (no mid-batch resume without a finer
sub-cursor anyway), needs a new column every writer must remember to bump, and ties feed
granularity to ingest batching — winning only on the consistency gap below, which ohfec never
hits.

`updated_at`'s one hazard is the **commit-ordering gap** (a row written at `T-1` in a
transaction committing after a consumer synced past `T` is missed). Neutralized by serving the
feed **bounded above by the last completed ingest run** — "changes since `<cursor>`, up to the
last finished batch" — so an in-flight batch's writes are never exposed mid-ingest. The
release-month idea survives here not as the cursor but as that **consistency watermark**.

Consequences: the **event type is derived from row state** (`tombstoned_at` set → tombstone;
`superseded_by_id` set → superseded; else upsert), no event log needed — we never hard-delete
(D10), so tombstoned/superseded rows stay in the table and re-emit on their bumped
`updated_at`. First sync uses cursor `0` (the bulk snapshot). **Accepted tradeoff:** a consumer
sees a row's *current* state, not every intermediate state between syncs — correct for a
facts-not-events source (D2/D4); history pointers carry the sequence. Per-change granularity, if
ever needed, is the trigger for an append-only event log (Phase 2+). Resolves the open cursor
item; amendment supersede (deferred in D15) composes with this for free — setting
`superseded_by` bumps `updated_at`, re-emitting the old filing as a status change.

## D17 — Sync feed is AshJsonApi; watermark realized as a safety lag

The changed-since feed (`/api/v1/sync/{organizations,people,filings,addresses}`) is
**AshJsonApi**, not hand-rolled Phoenix JSON. **Why:** Ash keyset pagination *is* the D16
cursor — `page[after]` over a `(updated_at, id)` sort — so the cursor mechanism is native and
opaque; endpoints/filtering/serialization generate from the resources we already have. The
bespoke bits are idiomatic Ash: a shared `ChangedSince` preparation (watermark filter +
`(updated_at, id)` sort + loads `event_type`) and an `event_type` calculation per resource
(derived from `tombstoned_at`/`superseded_by_id`; a constant `:upsert` for the non-history
`Address`). Hand-rolling would give a leaner envelope but reinvent pagination/serialization for
no real gain at this scale. (AshGraphql was never the fit — cursor-based bulk sync over GraphQL
is awkward.) Resolves the Ash-generated-vs-hand-rolled open item.

D16's "bounded by the last completed ingest run" is realized as a **safety lag**
(`Ingest.SyncWatermark`, `now - lag`, default 15 min) — because the 990 parse fans out into
async Oban jobs with no crisp completion instant, "last completed run" isn't cleanly
observable, whereas "older than a few minutes" guarantees every write's transaction has
committed. Same invariant (never serve an in-flight batch), simpler mechanism; invisible at
monthly cadence. Amendment supersede (deferred in D15) now ships alongside
(`EfileSupersedeWorker`) and re-emits via the feed for free.

Feed reads are **unauthenticated** by design (ARCHITECTURE); an interim Basic-auth gate for the
early-access window is a follow-up (see TODO).

## D18 — Data-source licensing posture: IRS public domain + Data Lake ODbL, ProPublica excluded

Full analysis in [LICENSING.md](LICENSING.md); the locked posture:

- **Core data is unencumbered.** BMF (irs.gov) and the 990 XML *content* are IRS public domain
  (17 U.S.C. § 105) — freely usable and commercializable. The 990 corpus is *accessed* via the
  GivingTuesday Data Lake, whose **index/curation is ODbL** (attribution + share-alike); ODbL
  governs their compilation, not the public-domain returns we serve.
- **ODbL is compatible because we're open** (VISION). ODbL permits commercial use + charging for
  access; it only requires the database stay open + attributed. So: license Nonprofiteer's own
  dataset ODbL, **attribute IRS + GivingTuesday**, and charge for hosted access — GuideStar's
  model over the same public data. You can't own public records.
- **ProPublica is never in the pipeline or served data** — its ToS forbids charging, redistributing,
  and reselling. Zero code references; keep it a manual dev cross-check only.
- **Never ingest legally non-public 990 data** — Schedule B donor names, SSNs, etc. Phase 2
  schedules use a public-field *allowlist*, not a denylist.
- **Before any paid launch, confirm with counsel** — chiefly whether index-driven ingestion makes
  our whole DB an ODbL "derivative database." Exit path if we ever go proprietary: source XML from
  IRS directly (~2–3 days, fetch layer only; availability already covered by D11's mirror).

## Open (not yet decided)

- *(none blocking — a paid launch needs counsel sign-off on the D18 ODbL question, not an
  engineering decision.)*
