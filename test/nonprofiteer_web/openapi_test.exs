defmodule NonprofiteerWeb.OpenApiTest do
  use NonprofiteerWeb.ConnCase, async: true

  # Regression guard: a bare-atom calculation (`expr(:upsert)`) was read by the DSL as a
  # calculation *module*, crashing OpenAPI generation (and the addresses sync feed) with
  # `could not load module :upsert`. These assert the spec builds and is served.

  test "AshJsonApi.OpenApi.spec/1 builds for the sync-feed domain" do
    spec = AshJsonApi.OpenApi.spec(domains: [Nonprofiteer.Orgs])

    assert map_size(spec.paths) > 0
    assert map_size(spec.components.schemas) > 0
  end

  test "GET /api/v1/open_api serves a JSON OpenAPI document", %{conn: conn} do
    # The AshJsonApi open_api route sets no content-type, so decode the raw body rather than
    # `json_response/2` (which requires a JSON content-type header).
    conn = get(conn, "/api/v1/open_api")
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)

    assert body["openapi"] =~ "3."
    assert is_map(body["paths"])
    assert Map.has_key?(body["paths"], "/api/v1/sync/addresses")
  end

  test "offline mix-task spec is byte-identical to the live-served document", %{conn: conn} do
    live = conn |> get("/api/v1/open_api") |> Map.fetch!(:resp_body)

    offline =
      [
        domains: [Nonprofiteer.Orgs],
        prefix: "/api/v1",
        phoenix_endpoint: NonprofiteerWeb.Endpoint,
        # Must mirror the mix task + live router, both of which fold in the custom routes.
        modify_open_api: {NonprofiteerWeb.OpenApiExtensions, :add_filing_source, []}
      ]
      |> AshJsonApi.OpenApi.spec()
      |> Jason.encode!(pretty: true)

    assert offline == live
  end
end
