defmodule Nonprofiteer.Orgs.Address do
  @moduledoc """
  A normalized postal address, attached to organizations and (via Part VII) people.

  Kept as its own resource so a shared address can be corroborated across records — part of
  the corroboration guarantee every emitted Org/Person ships with (D8).
  """
  use Ash.Resource,
    otp_app: :nonprofiteer,
    domain: Nonprofiteer.Orgs,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  @type t :: %__MODULE__{}

  json_api do
    type "address"

    routes do
      base "/sync/addresses"
      index :changed_since
    end
  end

  postgres do
    table "addresses"
    repo Nonprofiteer.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :line1, :string, public?: true
    attribute :line2, :string, public?: true
    attribute :city, :string, public?: true
    attribute :region, :string, public?: true
    attribute :postal_code, :string, public?: true
    attribute :country, :string, public?: true, default: "US"

    timestamps()
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    read :changed_since do
      description "Sync feed (D16): records changed up to the watermark, keyset-ordered."
      pagination keyset?: true, default_limit: 200, max_page_size: 2000, required?: false
      prepare Nonprofiteer.Orgs.Preparations.ChangedSince
    end
  end

  calculations do
    # Addresses aren't history-bearing (no tombstone/supersede), so the sync-feed event is
    # always `:upsert` — present for a uniform feed shape across resources (D16).
    # `type(:upsert, :atom)`, not a bare `:upsert`: a lone atom is read by the DSL as a
    # calculation *module* named `:upsert`, which crashes on load and in OpenAPI generation.
    calculate :event_type, :atom, expr(type(:upsert, :atom)) do
      public? true
      constraints one_of: [:upsert]
      description "Sync-feed status — always `:upsert` for addresses."
    end
  end
end
