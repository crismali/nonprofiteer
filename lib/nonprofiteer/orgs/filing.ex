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
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    fragments: [Nonprofiteer.Orgs.Fragments.SyncFeed, Nonprofiteer.Orgs.Fragments.SoftDelete]

  @type t :: %__MODULE__{}

  json_api do
    type "filing"

    routes do
      base "/sync/filings"
      index :changed_since
    end
  end

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

    attribute :filed_on, :date do
      public? true
      description "Filing date from the Data Lake index — orders amendments within a tax year."
    end

    attribute :schema_version, :string do
      public? true
      description ~s(IRS return schema version, e.g. "2021v4.0" — provenance + parse dispatch.)
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

    create :upsert_from_efile do
      description """
      Idempotent 990 e-file ingest entry point. Upserts on the `:unique_source_object_id`
      identity so a re-parse of the same Data Lake return converges. Amendment supersede is a
      deferred follow-up — amended returns land here as distinct filings (their own OBJECT_ID),
      with no data lost (D10).
      """

      upsert? true
      upsert_identity :unique_source_object_id
      upsert_fields [:return_type, :tax_year, :filed_on, :schema_version, :organization_id]

      accept [
        :return_type,
        :tax_year,
        :source_object_id,
        :filed_on,
        :schema_version,
        :organization_id
      ]
    end
  end

  # A Data Lake OBJECT_ID is globally unique per filing, so the e-file parse upserts on it —
  # a re-parse of the same return converges instead of duplicating. Nullable-friendly: filings
  # created by other paths (tests) without a source id aren't constrained (Postgres treats the
  # nulls as distinct).
  identities do
    identity :unique_source_object_id, [:source_object_id]
  end
end
