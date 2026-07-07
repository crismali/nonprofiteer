defmodule NonprofiteerWeb.OpenApiExtensionsTest do
  use NonprofiteerWeb.ConnCase, async: true

  alias NonprofiteerWeb.OpenApiExtensions

  @source_path "/api/v1/filings/{id}/source"

  test "add_filing_source/1 injects the raw-source path into an existing spec" do
    spec = %OpenApiSpex.OpenApi{
      info: %OpenApiSpex.Info{title: "t", version: "1"},
      paths: %{"/api/v1/sync/filings" => %OpenApiSpex.PathItem{}}
    }

    modified = OpenApiExtensions.add_filing_source(spec)

    # Existing paths are preserved; ours is added with a documented GET operation.
    assert Map.has_key?(modified.paths, "/api/v1/sync/filings")

    assert %OpenApiSpex.PathItem{get: %OpenApiSpex.Operation{} = op} =
             modified.paths[@source_path]

    assert op.operationId == "getFilingSource"
    assert Map.has_key?(op.responses, 200)
  end

  test "the live GET /api/v1/open_api document includes the custom route", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/open_api")

    paths = conn |> response(200) |> Jason.decode!() |> Map.fetch!("paths")

    assert Map.has_key?(paths, @source_path)
    assert get_in(paths, [@source_path, "get", "operationId"]) == "getFilingSource"
  end
end
