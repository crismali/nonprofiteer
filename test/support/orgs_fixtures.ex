defmodule Nonprofiteer.OrgsFixtures do
  @moduledoc "Test fixtures for `Nonprofiteer.Orgs` resources."

  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Organization

  @doc "Creates an `Organization`; defaults the name so callers that don't care can omit it."
  def create_org(attrs \\ %{name: "ACME Foundation"}) do
    Organization |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  @doc """
  Creates a `Filing` for `org`, defaulting the required tax year. Merge `attrs` (e.g.
  `source_object_id`) for what the test cares about.
  """
  def create_filing(org, attrs \\ %{}) do
    defaults = %{organization_id: org.id, tax_year: 2020}

    Filing
    |> Ash.Changeset.for_create(:upsert_from_efile, Map.merge(defaults, attrs))
    |> Ash.create!()
  end
end
