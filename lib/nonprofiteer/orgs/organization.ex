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
  end

  attributes do
    uuid_primary_key :id

    attribute :ein, :string do
      public? true
      description "IRS Employer Identification Number. Indexed, cardinality 0/1/many (D7)."
    end

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :ntee_code, :string, public?: true

    attribute :tombstoned_at, :utc_datetime_usec do
      public? true
      description "When set, this org was withdrawn (soft delete) — see the `:tombstone` action."
    end

    timestamps()
  end

  relationships do
    belongs_to :address, Nonprofiteer.Orgs.Address, public?: true

    belongs_to :central_org, __MODULE__ do
      public? true
      description "For a group-exemption subordinate, the central org it falls under (D7)."
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
  end
end
