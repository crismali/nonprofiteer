defmodule Nonprofiteer.Orgs do
  @moduledoc """
  The organizations domain — the org spine (`Organization`) plus normalized `Address`es.

  This is the public entry point for the resources it groups: call them through this domain
  (or `Ash.*` with the resource module), not by poking at the resources directly.
  """
  use Ash.Domain, otp_app: :nonprofiteer, extensions: [AshJsonApi.Domain]

  # The changed-since sync feed (D3/D16). Each resource declares its own `json_api` routes; this
  # extension makes the domain routable by `NonprofiteerWeb.AshJsonApiRouter` (mounted at
  # `/api/v1` in the Phoenix router).
  json_api do
  end

  resources do
    resource Nonprofiteer.Orgs.Address
    resource Nonprofiteer.Orgs.Organization
    resource Nonprofiteer.Orgs.Filing
    resource Nonprofiteer.Orgs.Person
  end
end
