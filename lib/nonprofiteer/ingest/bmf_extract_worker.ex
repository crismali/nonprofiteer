defmodule Nonprofiteer.Ingest.BmfExtractWorker do
  @moduledoc """
  Downloads one EO BMF extract, parses it, and upserts the organizations (with their
  addresses) into the spine — writing an `Ingest.Run` audit row on both success and failure.

  Idempotent: the org upsert keys on the partial `:unique_bmf_ein` identity, and the org's
  address is created once then updated in place on re-runs, so a monthly re-download converges
  instead of duplicating. Rows without an EIN can't anchor to the spine and are counted as
  orphan skips rather than dropped silently.
  """
  use Oban.Worker,
    queue: :ingest_bulk,
    max_attempts: 5,
    unique: [keys: [:extract_id], period: {1, :hour}]

  alias Nonprofiteer.Ingest.Batch
  alias Nonprofiteer.Ingest.Bmf
  alias Nonprofiteer.Ingest.Client
  alias Nonprofiteer.Ingest.Run
  alias Nonprofiteer.Orgs.Address
  alias Nonprofiteer.Orgs.Organization

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"url" => url, "extract_id" => extract_id}}) do
    case import_extract(url) do
      {:ok, {row_count, orphan_skipped}} ->
        record_run!(%{
          extract_id: extract_id,
          status: :success,
          row_count: row_count,
          orphan_skipped_count: orphan_skipped
        })

        :ok

      {:error, {row_count, orphan_skipped}, exception, stacktrace} ->
        record_run!(%{
          extract_id: extract_id,
          # `:partial` when some orgs upserted before the failure, `:failure` when none did
          # (e.g. the download/parse itself failed) — so the audit row can't hide committed rows.
          status: if(row_count > 0, do: :partial, else: :failure),
          row_count: row_count,
          orphan_skipped_count: orphan_skipped,
          error_message: Exception.message(exception)
        })

        reraise exception, stacktrace
    end
  end

  # `{:ok, counts}` | `{:error, counts, exception, stacktrace}`, matching `Batch.reduce/3`. A
  # download/parse failure yields `{0, 0}` counts (nothing imported); a mid-batch upsert failure
  # yields the counts committed before it.
  @spec import_extract(String.t()) :: Batch.result()
  defp import_extract(url) do
    rows =
      url
      |> Client.fetch!()
      |> Bmf.parse!()

    Batch.reduce(rows, {0, 0}, &import_row/2)
  rescue
    exception -> {:error, {0, 0}, exception, __STACKTRACE__}
  end

  # Upserts one parsed row, tallying a successful upsert vs. an EIN-less orphan skip.
  defp import_row(%{org: %{ein: nil}}, {ok, orphan}), do: {ok, orphan + 1}

  defp import_row(%{org: org_attrs, address: address_attrs}, {ok, orphan}) do
    org_attrs
    |> upsert_org!()
    |> link_address!(address_attrs)

    {ok + 1, orphan}
  end

  defp upsert_org!(org_attrs) do
    Organization
    |> Ash.Changeset.for_create(:upsert_from_bmf, org_attrs)
    |> Ash.create!()
  end

  # First sighting of this org: create its address and link it. Re-run: update the already
  # linked address in place, so no orphan address rows accumulate month over month.
  defp link_address!(%Organization{address_id: nil} = org, address_attrs) do
    address =
      Address
      |> Ash.Changeset.for_create(:create, address_attrs)
      |> Ash.create!()

    org
    |> Ash.Changeset.for_update(:update, %{address_id: address.id})
    |> Ash.update!()
  end

  defp link_address!(%Organization{address_id: address_id}, address_attrs) do
    Address
    |> Ash.get!(address_id)
    |> Ash.Changeset.for_update(:update, address_attrs)
    |> Ash.update!()
  end

  defp record_run!(attrs) do
    Run.record!(Map.put(attrs, :source, :bmf))
  end
end
