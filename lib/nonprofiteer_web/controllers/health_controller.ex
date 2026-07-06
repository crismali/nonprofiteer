defmodule NonprofiteerWeb.HealthController do
  @moduledoc """
  Unauthenticated liveness/readiness probe for deploy + monitoring.

  Stays open even once API keys gate the sync feed — monitors need it reachable. Reports DB
  reachability (the last-ingest-run lookup doubles as the probe) and the most recent ingest
  run's timestamp, so a monitor can alert both on the app being down (503 / no response) and on
  ingest having silently stalled (a stale or null `last_ingest_run_at`).
  """
  use NonprofiteerWeb, :controller

  alias Nonprofiteer.Ingest.Run

  @doc "GET /health — 200 when the DB is reachable, 503 otherwise."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    case last_ingest_run_at() do
      {:ok, last_ingest_run_at} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok", database: "ok", last_ingest_run_at: last_ingest_run_at})

      :error ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", database: "error", last_ingest_run_at: nil})
    end
  end

  # Newest ingest run's timestamp (nil if none yet). Any failure — a DB that's down most of all
  # — surfaces as `:error`, which drives the 503.
  @spec last_ingest_run_at() :: {:ok, DateTime.t() | nil} | :error
  defp last_ingest_run_at do
    run =
      Run
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read_one!()

    {:ok, run && run.inserted_at}
  rescue
    _exception -> :error
  end
end
