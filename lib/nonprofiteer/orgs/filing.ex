defmodule Nonprofiteer.Orgs.Filing do
  @moduledoc """
  A single submitted information return (990 / 990-EZ / 990-PF) for an organization in a tax year.

  Carries the **provenance pointer** (`source_object_id`) back to the mirrored source document
  (D11), and is itself what `Person` records point at as their source filing (D8). Amendments
  are modeled as history, not overwrites: a superseding return points the prior one forward via
  `superseded_by`, withdrawals set `tombstoned_at`, and there is no hard `:destroy` (D10).
  """
  use Ash.Resource,
    otp_app: :nonprofiteer,
    domain: Nonprofiteer.Orgs,
    data_layer: AshPostgres.DataLayer

  @type t :: %__MODULE__{}

  postgres do
    table "filings"
    repo Nonprofiteer.Repo

    custom_indexes do
      index [:organization_id]
      index [:tax_year]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :return_type, :atom do
      public? true
      constraints one_of: [:form_990, :form_990_ez, :form_990_pf]
      description "Which information return this is."
    end

    attribute :tax_year, :integer, allow_nil?: false, public?: true

    attribute :source_object_id, :string do
      public? true
      description "Pointer to the mirrored source XML / IRS DLN — provenance (D11)."
    end

    attribute :tombstoned_at, :utc_datetime_usec do
      public? true

      description "When set, this filing was withdrawn (soft delete) — see the `:tombstone` action."
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, Nonprofiteer.Orgs.Organization, allow_nil?: false, public?: true

    has_many :people, Nonprofiteer.Orgs.Person, public?: true

    belongs_to :superseded_by, __MODULE__ do
      public? true
      description "The filing that supersedes this one — an amendment (D10)."
    end
  end

  actions do
    # No `:destroy` — history is never hard-deleted (D10); use `:tombstone` instead.
    defaults [:read, create: :*, update: :*]

    update :tombstone do
      description "Soft-delete: mark the filing withdrawn without destroying history (D10)."
      accept []
      require_atomic? false
      change set_attribute(:tombstoned_at, &DateTime.utc_now/0)
    end
  end
end
