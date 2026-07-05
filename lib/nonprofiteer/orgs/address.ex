defmodule Nonprofiteer.Orgs.Address do
  @moduledoc """
  A normalized postal address, attached to organizations and (via Part VII) people.

  Kept as its own resource so a shared address can be corroborated across records — part of
  the corroboration guarantee every emitted Org/Person ships with (D8).
  """
  use Ash.Resource,
    otp_app: :nonprofiteer,
    domain: Nonprofiteer.Orgs,
    data_layer: AshPostgres.DataLayer

  @type t :: %__MODULE__{}

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
  end
end
