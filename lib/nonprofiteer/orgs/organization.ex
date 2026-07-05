defmodule Nonprofiteer.Orgs.Organization do
  @moduledoc """
  A tax-exempt organization — the spine of the dataset.

  Identified by a Nonprofiteer-owned **surrogate id**, not its EIN: an EIN may be absent,
  shared (group exemptions), or reissued (reorganizations), so `ein` is an indexed attribute
  with cardinality 0/1/many, never the primary key (D7). Central-vs-subordinate structure is
  modeled explicitly via `central_org`.

  History is preserved, never destroyed (D10): reorganizations/merges point forward via
  `superseded_by`, withdrawals set `tombstoned_at` through the `:tombstone` action, and the
  resource deliberately exposes no hard `:destroy`.
  """
  use Ash.Resource,
    otp_app: :nonprofiteer,
    domain: Nonprofiteer.Orgs,
    data_layer: AshPostgres.DataLayer

  @type t :: %__MODULE__{}

  postgres do
    table "organizations"
    repo Nonprofiteer.Repo

    # EIN is looked up often but is NOT unique (D7) — index it, don't constrain it.
    custom_indexes do
      index [:ein]
    end

    # Hand SQL for the `:unique_bmf_ein` partial-index predicate — ash_postgres can't infer it
    # from the Ash `where` expression, so the two must be kept in lockstep by hand.
    identity_wheres_to_sql unique_bmf_ein: "source = 'bmf'"
  end

  attributes do
    uuid_primary_key :id

    attribute :ein, :string do
      public? true
      description "IRS Employer Identification Number. Indexed, cardinality 0/1/many (D7)."
    end

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :ntee_code, :string, public?: true

    attribute :source, :atom do
      public? true
      constraints one_of: [:bmf]

      description """
      Ingest provenance — which pipeline seeded/last-touched this org. Nullable: orgs first
      seen via a non-BMF path (later 990 XML) carry no source. The BMF upsert keys on
      `[:source, :ein]` as a partial unique identity, so EIN stays globally non-unique (D7).
      """
    end

    attribute :gen, :string do
      public? true

      description """
      IRS Group Exemption Number from the BMF. Links group-exemption subordinates to their
      central org (D7); the central-vs-subordinate wiring off this is a later reconcile pass.
      """
    end

    attribute :affiliation_code, :string do
      public? true

      description """
      Raw BMF AFFILIATION code. A group's central org (6/8) and its subordinates (9) share the
      same `gen`, so this code is what tells them apart — it drives the later GEN→`central_org`
      reconcile. Stored raw; interpretation lives in that pass.
      """
    end

    attribute :tombstoned_at, :utc_datetime_usec do
      public? true
      description "When set, this org was withdrawn (soft delete) — see the `:tombstone` action."
    end

    timestamps()
  end

  relationships do
    belongs_to :address, Nonprofiteer.Orgs.Address do
      public? true
      # BMF ingest links the org to its address after upsert, then updates that same address
      # row in place on re-runs — so the FK must be directly writable via an update action.
      attribute_writable? true
    end

    belongs_to :central_org, __MODULE__ do
      public? true
      description "For a group-exemption subordinate, the central org it falls under (D7)."
      # The post-ingest GEN reconcile (D13) sets this FK directly on already-persisted
      # subordinates, so it must be writable via an update action.
      attribute_writable? true
    end

    has_many :subordinates, __MODULE__ do
      public? true
      destination_attribute :central_org_id
    end

    has_many :filings, Nonprofiteer.Orgs.Filing, public?: true
    has_many :people, Nonprofiteer.Orgs.Person, public?: true

    belongs_to :superseded_by, __MODULE__ do
      public? true
      description "The organization record that supersedes this one — amendment/merge (D10)."
    end
  end

  actions do
    # No `:destroy` — history is never hard-deleted (D10); use `:tombstone` instead.
    defaults [:read, create: :*, update: :*]

    update :tombstone do
      description "Soft-delete: mark the org withdrawn without destroying history (D10)."
      accept []
      require_atomic? false
      change set_attribute(:tombstoned_at, &DateTime.utc_now/0)
    end

    create :upsert_from_bmf do
      description """
      Idempotent BMF ingest entry point. Upserts on the partial `:unique_bmf_ein` identity so
      a monthly re-run over the full extract converges instead of duplicating. Only the
      registry-mutable fields overwrite on conflict; the surrogate id, `source`, and the org's
      address linkage are left to first-insert / the worker's address reconcile.
      """

      upsert? true
      upsert_identity :unique_bmf_ein
      upsert_fields [:name, :ntee_code, :gen, :affiliation_code]

      accept [:ein, :name, :ntee_code, :gen, :affiliation_code]
      change set_attribute(:source, :bmf)
    end
  end

  # A BMF extract is one row per EIN, so BMF-sourced orgs must upsert on EIN to stay
  # idempotent across monthly re-runs. This identity is *partial* (`where: source == :bmf`),
  # backing a partial unique index — EIN remains globally non-unique (D7) so future
  # non-BMF sources can still introduce shared/reissued EINs.
  identities do
    identity :unique_bmf_ein, [:ein], where: expr(source == :bmf)
  end
end
