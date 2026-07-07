defmodule Mix.Tasks.Nonprofiteer.Openapi do
  @shortdoc "Writes the JSON:API sync feed's OpenAPI (Swagger) spec to a file"

  @moduledoc """
  Generates the OpenAPI 3 spec for the public sync feed — the same document served live at
  `GET /api/v1/open_api` — and writes it to disk as pretty-printed JSON. Handy for handing a
  static contract to a consumer (e.g. the sibling **ohfec** project's EIN-matching bridge)
  without pointing it at a running server.

      mix nonprofiteer.openapi              # → openapi.json in the project root
      mix nonprofiteer.openapi priv/static/openapi.json

  Builds the spec straight from the compiled `Nonprofiteer.Orgs` resources' `json_api` routes
  via `AshJsonApi.OpenApi.spec/1`, passing the router mount prefix and endpoint so the output is
  byte-identical to the live `GET /api/v1/open_api` document (the `servers` URL is read from the
  running endpoint's config — hence the app is booted).
  """

  use Mix.Task

  # Boots the app so the spec is byte-identical to what `GET /api/v1/open_api` serves: the
  # `servers` entry is derived from the started endpoint's URL config (which only exists at
  # runtime), matching the live route's logic.
  @requirements ["app.start"]

  @default_path "openapi.json"

  # Domains whose resources expose `json_api` routes — the ones the sync-feed router mounts.
  @domains [Nonprofiteer.Orgs]

  # Where the JSON:API router is forwarded in `NonprofiteerWeb.Router` — the live route infers
  # this from the request path; offline we pass it explicitly so paths carry the same prefix.
  @mount_prefix "/api/v1"

  @doc false
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    path =
      case args do
        [path | _] -> path
        [] -> @default_path
      end

    json =
      [
        domains: @domains,
        prefix: @mount_prefix,
        phoenix_endpoint: NonprofiteerWeb.Endpoint,
        # Same hook the live router uses, so the handoff spec includes the custom (non-Ash)
        # routes and stays byte-identical to `GET /api/v1/open_api`.
        modify_open_api: {NonprofiteerWeb.OpenApiExtensions, :add_filing_source, []}
      ]
      |> AshJsonApi.OpenApi.spec()
      |> Jason.encode!(pretty: true)

    File.write!(path, json)
    Mix.shell().info("Wrote OpenAPI spec to #{path}")

    :ok
  end
end
