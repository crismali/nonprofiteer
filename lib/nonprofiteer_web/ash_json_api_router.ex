defmodule NonprofiteerWeb.AshJsonApiRouter do
  @moduledoc """
  JSON:API router for the public sync feed — the changed-since endpoints generated from the
  `Nonprofiteer.Orgs` resources' `json_api` routes. Mounted at `/api/v1` in the Phoenix router.
  """
  use AshJsonApi.Router,
    domains: [Nonprofiteer.Orgs],
    open_api: "/open_api"
end
