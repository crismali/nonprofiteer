defmodule NonprofiteerWeb.FilingSourceController do
  @moduledoc """
  Serves the mirrored source 990 XML for a filing — provenance/trust (D11).

  The IRS e-file XML is public domain, so it's the safest, most open thing we redistribute. We
  **proxy** it from our R2 mirror rather than redirect, keeping the bucket private and the URL
  stable (`GET /api/v1/filings/:id/source`). Returns are small (KB–low-MB), so the body is
  buffered and sent whole.

  Unauthenticated for now, matching the sync feed; it joins the API-key gate when that lands
  (unlike `/health`, this is data). Error mapping keeps the causes distinct: an unknown filing
  or one with no mirrored source is a **404**; a dormant mirror (R2 unconfigured) is a **503**;
  an object the mirror should hold but can't return is a **502**.
  """
  use NonprofiteerWeb, :controller

  alias Nonprofiteer.Ingest.ObjectStore
  alias Nonprofiteer.Orgs.Filing

  @doc "GET /api/v1/filings/:id/source — streams the R2-mirrored source XML for the filing."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    case filing_source_object_id(id) do
      {:ok, object_id} -> serve_source(conn, object_id)
      :error -> send_error(conn, :not_found, "filing not found or has no mirrored source")
    end
  end

  # `{:ok, object_id}` only for a real filing that carries a source pointer; anything else — bad
  # id, unknown id, or a filing with no `source_object_id` — collapses to `:error` → 404.
  defp filing_source_object_id(id) do
    case Ash.get(Filing, id) do
      {:ok, %Filing{source_object_id: object_id}} when is_binary(object_id) -> {:ok, object_id}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp serve_source(conn, object_id) do
    case ObjectStore.get("efile/#{object_id}.xml") do
      {:ok, xml} ->
        send_xml(conn, object_id, xml)

      {:error, :not_configured} ->
        send_error(conn, :service_unavailable, "source mirror not configured")

      {:error, :not_found} ->
        send_error(conn, :not_found, "source document not found in mirror")

      {:error, _reason} ->
        send_error(conn, :bad_gateway, "source mirror unavailable")
    end
  end

  defp send_xml(conn, object_id, xml) do
    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(inline; filename="#{object_id}.xml"))
    # Source documents are immutable once filed, so they cache forever.
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> send_resp(200, xml)
  end

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end
end
