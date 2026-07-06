---
name: ash
description: Expert in Ash Framework 3.x resource modeling, actions, policies, and ash_postgres/ash_phoenix integration
---

# Ash

You are an expert in Ash Framework 3.x — declarative resource modeling on top of Ecto, with `ash_postgres` for persistence and `ash_phoenix` for LiveView/form integration. This project tracks the latest Ash 3.x (3.29 at time of writing) rather than pinning down — per [CLAUDE.md](../../../CLAUDE.md), bump *up* to resolve conflicts.

> The Phase-1 resources now exist under the `Nonprofiteer.Orgs` domain: `Organization`, `Address`, `Filing`, `Person` (`lib/nonprofiteer/orgs/`). Read those for the real, current patterns; the examples below are illustrative.

**Inspect a compiled resource fast:** `mix nonprofiteer.resources Organization` prints its shape (attributes + types, relationships, actions, identities, calcs) without opening the source and every file it relates to. No argument lists all resources by domain. Reach for this before reading resource source.

## Core principles

- Resources are the unit of modeling, not Ecto schemas directly — define data shape, actions, and authorization together in one DSL block.
- Prefer Ash's generic actions/calculations/changes over hand-rolled context functions where the work fits the DSL — that's the reason this project uses Ash at all.
- Domains (`Ash.Domain`) group resources and expose the public API other code calls (`Nonprofiteer.Orgs.get_organization!/1`), not raw `Ash.Resource` functions called directly.

## Resource definition

```elixir
defmodule Nonprofiteer.Orgs.Organization do
  use Ash.Resource,
    otp_app: :nonprofiteer,
    domain: Nonprofiteer.Orgs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "organizations"
    repo Nonprofiteer.Repo
  end

  attributes do
    uuid_primary_key :id
    # EIN is an indexed attribute, cardinality 0/1/many — NOT the primary key (D7).
    attribute :ein, :string, public?: true
    attribute :name, :string, public?: true
    timestamps()
  end

  relationships do
    # Central-vs-subordinate modeled explicitly: a subordinate points at its central org.
    belongs_to :central_org, __MODULE__
    has_many :filings, Nonprofiteer.Orgs.Filing
  end

  actions do
    defaults [:read, :destroy]
    default_accept [:ein, :name]
    create :create
    update :update
  end
end
```

- `public?: true` required for an attribute to be exposed via `AshPhoenix.Form`/`AshJsonApi` — default is private.
- `identities do ... end` block for unique constraints — but **do not** add `identity :unique_ein, [:ein]` here: EIN cardinality is 0/1/many by design (group exemptions, reorganizations), so uniqueness lives on the surrogate id, not the EIN (D7). Index EIN for lookup, don't constrain it unique.

## Actions vs changesets

- Actions (`create`/`read`/`update`/`destroy`/generic) are the only entry points — never bypass them with `Repo.insert` directly on an Ash-backed schema. This matters doubly for the ingest pipeline: BMF/Part VII upserts must go through actions so provenance/history logic (`superseded_by`, source-filing pointer, D8/D10) runs.
- `change` blocks/modules (`Ash.Resource.Change`) run logic during create/update — analogous to `Ecto.Changeset` pipelines but declared per-action.
- `Ash.Changeset.before_action/after_action` for imperative hooks when a DSL builtin doesn't fit (e.g. attaching a source-filing pointer during an ingest action).
- Call actions via the domain's generated code interface (`define :create, action: :create` in the domain) or `Ash.create!/Ash.read!/Ash.update!/Ash.destroy!` directly — pick one calling convention per domain and stay consistent.

## Upserts (the ingest workhorse)

BMF ingest re-runs monthly over the full org set, so create actions should upsert rather than blow up on the existing row:

```elixir
create :upsert_from_bmf do
  upsert? true
  upsert_identity :unique_bmf_key   # the identity that keys the source record
  upsert_fields [:name, :address_id, :ntee_code]
end
```

- Choose the upsert identity deliberately — for orgs it's the source's stable key, not EIN. Verify the identity exists before referencing it in `upsert_identity`.
- `upsert_fields` controls what a conflicting row overwrites — omit fields you want write-once (e.g. the surrogate id, first-seen timestamp).

## Policies

```elixir
policies do
  policy action_type(:read) do
    authorize_if always()
  end

  policy action_type([:create, :update, :destroy]) do
    authorize_if actor_attribute_equals(:role, :admin)
  end
end
```

- Policies are additive checks evaluated per request — `authorize_if`/`forbid_if`/`forbid_unless`. No policy block = allow by default unless `authorize :always` is set at the resource level (set this explicitly rather than relying on the default).
- Public sync-feed/API reads are unauthenticated by design; write actions (ingest) run from trusted Oban workers. Keep read policies open and write policies tight rather than a blanket default.

## Calculations & aggregates

- `calculations do calculate :full_name, :string, expr(first_name <> " " <> last_name) end` for derived attributes computable in Postgres.
- `aggregates do count :filing_count, :filings end` for relationship rollups — avoids hand-written `Ecto.Query` joins for simple counts/sums/exists checks.

## Sharing DSL across resources

- When the same DSL block repeats verbatim across resources (this project's `:changed_since`
  sync-feed action, the `tombstoned_at` + `:tombstone` + `event_type` soft-delete trio), extract
  it into a **Spark DSL fragment** rather than copy-pasting:
  ```elixir
  defmodule Nonprofiteer.Orgs.Fragments.SyncFeed do
    use Spark.Dsl.Fragment, of: Ash.Resource
    actions do
      read :changed_since do
        pagination keyset?: true, default_limit: 200, required?: false
        prepare Nonprofiteer.Orgs.Preparations.ChangedSince
      end
    end
  end
  ```
  ```elixir
  use Ash.Resource,
    domain: Nonprofiteer.Orgs,
    fragments: [Nonprofiteer.Orgs.Fragments.SyncFeed]
  ```
  Fragments merge section-by-section into the resource DSL at compile time, so `attributes`,
  `actions`, `calculations`, etc. combine with whatever the resource also declares.
- **`__MODULE__` gotcha:** inside a fragment it resolves to the *fragment* module, not the
  resource. So a self-referential `belongs_to :superseded_by, __MODULE__` **cannot** live in a
  fragment — keep it on each resource. An `expr` that *references* such a relationship's FK
  (e.g. `superseded_by_id` in `event_type`) is fine in a fragment: the column exists in the
  merged resource, and merge happens before validation.
- A fragment can't be run through the code interface itself — it has no `domain:`; it only
  contributes DSL to resources that list it.
- After extracting to fragments, run `mix ash.codegen --check` (or
  `mix ash_postgres.generate_migrations`) — a clean result confirms the merged schema is
  identical and no migration is needed (attribute *order* moving between file and fragment does
  not change the generated table).

## Migrations

- Never hand-write Ecto migrations for Ash-backed tables. After changing a resource's `attributes`/`identities`/`relationships`:
  ```
  mix ash_postgres.generate_migrations --name descriptive_name
  mix ash.migrate
  ```
- Review the generated migration before running it — Ash infers a lot correctly, but the self-referential central/subordinate relationship and any `pg_trgm` indexes for fuzzy name/address search (D-bridge) are worth a manual sanity check.

## AshPhoenix / AshAdmin integration

- `ash_admin` is a dependency — the generated admin UI is the near-term way to eyeball ingested data. Keep resources' `public?`/action surface sane so admin renders them usefully.
- `AshPhoenix.Form.for_create/for_update` builds a Phoenix form from a resource action — use this instead of hand-rolling `Ecto.Changeset`-backed forms in the (later) LiveView UI.
- For read/filter pages, prefer `Ash.Query` + `Ash.read!` with `filter`/`sort`/`page` built from assigns over building raw `Ecto.Query`.

## Testing

- Generators: `Ash.Generator` or hand-written factory functions calling the resource's create action — avoid inserting fixture rows via `Repo.insert` directly, since that skips changes/validations the tests should also exercise.
- Test policies explicitly with distinct actor contexts (no actor, wrong-role actor, correct-role actor) — policy bugs fail silently as either over- or under-permissive, never as a crash.
- Coverage gate is 80% (`coveralls`) — ingest actions with provenance/history logic are exactly the code that must be covered, not scaffold.

## Gotchas

- `ash_postgres` migrations are generated, not autogenerated-and-applied — always run `mix ash.migrate` (or `mix ash.setup` for a fresh DB) as a separate step.
- Bulk actions (`Ash.bulk_create!`/`Ash.bulk_update!`) — heavily relevant to monthly batch ingest. Their raise-vs-`:error`-tuple behavior depends on Ash's `bulk_actions_default_to_errors?` config; this project does not set it in `config.exs`, so **check the current default for the installed Ash version** before assuming raise-on-error semantics in ingest jobs.
- `domain:` must be set on every resource — a resource with no domain can't be called through the generated code interface.
- The `Repo` installs `["ash-functions", "pg_trgm"]` extensions ([`lib/nonprofiteer/repo.ex`](../../../lib/nonprofiteer/repo.ex)) — `pg_trgm` is there for the fuzzy-match bridge to ohfec; add trigram indexes on name/address columns when those resources land.
