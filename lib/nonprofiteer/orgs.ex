defmodule Nonprofiteer.Orgs do
  @moduledoc """
  The organizations domain — the org spine (`Organization`) plus normalized `Address`es.

  This is the public entry point for the resources it groups: call them through this domain
  (or `Ash.*` with the resource module), not by poking at the resources directly.
  """
  use Ash.Domain, otp_app: :nonprofiteer

  resources do
    resource Nonprofiteer.Orgs.Address
    resource Nonprofiteer.Orgs.Organization
  end
end
