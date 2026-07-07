defmodule NonprofiteerWeb.OpenApiExtensions do
  @moduledoc """
  Hand-written OpenAPI paths that aren't generated from Ash resources.

  AshJsonApi builds the sync-feed spec straight from the `Nonprofiteer.Orgs` resources' JSON:API
  routes, so custom Phoenix routes (like the raw-source proxy) are invisible to it. This module
  is the `modify_open_api` hook that folds those routes back in, wired into **both** the live
  `GET /api/v1/open_api` router and the `mix nonprofiteer.openapi` handoff so the two stay
  byte-identical.
  """
  alias OpenApiSpex.MediaType
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Parameter
  alias OpenApiSpex.PathItem
  alias OpenApiSpex.Response
  alias OpenApiSpex.Schema

  # The generated paths carry the router mount prefix (e.g. "/api/v1/sync/filings"), so the
  # hand-added path uses it too, keeping every entry under one consistent prefix.
  @source_path "/api/v1/filings/{id}/source"

  @doc """
  `modify_open_api` callback — merges the custom paths into `spec.paths`. Arity matches
  AshJsonApi's `modify.(spec, conn, opts)` contract; `conn`/`opts` are unused here.
  """
  @spec add_filing_source(OpenApiSpex.OpenApi.t(), any(), any()) :: OpenApiSpex.OpenApi.t()
  def add_filing_source(spec, _conn \\ nil, _opts \\ nil) do
    %{spec | paths: Map.put(spec.paths, @source_path, filing_source_path_item())}
  end

  defp filing_source_path_item do
    %PathItem{
      get: %Operation{
        operationId: "getFilingSource",
        summary: "Raw source 990 XML for a filing",
        description:
          "Streams the IRS e-filed 990 XML mirrored for this filing (provenance, D11). " <>
            "The document is public-domain IRS data.",
        tags: ["filing"],
        parameters: [
          %Parameter{
            name: :id,
            in: :path,
            required: true,
            description: "The filing's id.",
            schema: %Schema{type: :string, format: :uuid}
          }
        ],
        responses: %{
          200 => %Response{
            description: "The mirrored source 990 XML.",
            content: %{"application/xml" => %MediaType{schema: %Schema{type: :string}}}
          },
          404 => %Response{description: "No such filing, or it has no mirrored source document."},
          503 => %Response{description: "The source mirror is not configured."}
        }
      }
    }
  end
end
