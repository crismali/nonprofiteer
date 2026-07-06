defmodule Nonprofiteer.OrgsFixtures do
  @moduledoc "Test fixtures for `Nonprofiteer.Orgs` resources."

  alias Nonprofiteer.Orgs.Organization

  @doc "Creates an `Organization`; defaults the name so callers that don't care can omit it."
  def create_org(attrs \\ %{name: "ACME Foundation"}) do
    Organization |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end
end
