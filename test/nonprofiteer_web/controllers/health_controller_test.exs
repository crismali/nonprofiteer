defmodule NonprofiteerWeb.HealthControllerTest do
  use NonprofiteerWeb.ConnCase, async: true

  alias Nonprofiteer.Ingest.Run

  test "GET /health is ok with a null last run when none have happened", %{conn: conn} do
    body = conn |> get("/health") |> json_response(200)

    assert body["status"] == "ok"
    assert body["database"] == "ok"
    assert body["last_ingest_run_at"] == nil
  end

  test "GET /health reports the newest ingest run's timestamp", %{conn: conn} do
    Run.record!(%{source: :bmf, extract_id: "old", status: :success})
    newest = Run.record!(%{source: :bmf, extract_id: "new", status: :success})

    body = conn |> get("/health") |> json_response(200)

    assert body["status"] == "ok"
    assert body["last_ingest_run_at"] == DateTime.to_iso8601(newest.inserted_at)
  end

  test "GET /health ignores the Accept header (open to bare monitors)", %{conn: conn} do
    body =
      conn
      |> put_req_header("accept", "text/plain")
      |> get("/health")
      |> json_response(200)

    assert body["status"] == "ok"
  end
end
