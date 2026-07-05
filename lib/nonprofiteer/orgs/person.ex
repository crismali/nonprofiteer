defmodule Nonprofiteer.Orgs.Person do
  @moduledoc """
  An officer, director, trustee, or key/highest-comp employee listed in a filing's **Part VII**.

  Every person record ships enough to be *matchable elsewhere* — an associated `address` and a
  `filing` source pointer (D8) — but Nonprofiteer does no matching itself. Compensation and
  tenure are Phase 2, deliberately out of scope here. History follows the same pattern as
  `Organization`/`Filing`: `superseded_by` + `:tombstone`, no hard `:destroy` (D10).
  """
  use Ash.Resource,
    otp_app: :nonprofiteer,
    domain: Nonprofiteer.Orgs,
    data_layer: AshPostgres.DataLayer

  @type t :: %__MODULE__{}

  postgres do
    table "people"
    repo Nonprofiteer.Repo

    custom_indexes do
      index [:organization_id]
      index [:filing_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :title, :string do
      public? true
      description ~s(Role/title as printed in Part VII, e.g. "PRESIDENT" or "TREASURER".)
    end

    attribute :tombstoned_at, :utc_datetime_usec do
      public? true
      description "When set, this person record was withdrawn (soft delete)."
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, Nonprofiteer.Orgs.Organization, allow_nil?: false, public?: true

    # Source-filing pointer — where this person record came from (D8 corroboration).
    belongs_to :filing, Nonprofiteer.Orgs.Filing, allow_nil?: false, public?: true

    belongs_to :address, Nonprofiteer.Orgs.Address, public?: true

    belongs_to :superseded_by, __MODULE__ do
      public? true
      description "The person record that supersedes this one (D10)."
    end
  end

  actions do
    # No `:destroy` — history is never hard-deleted (D10); use `:tombstone` instead.
    defaults [:read, create: :*, update: :*]

    update :tombstone do
      description "Soft-delete: mark the person record withdrawn without destroying history (D10)."
      accept []
      require_atomic? false
      change set_attribute(:tombstoned_at, &DateTime.utc_now/0)
    end
  end
end
