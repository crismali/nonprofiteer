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

  alias Nonprofiteer.Ingest.Bmf
  alias Nonprofiteer.Ingest.Client
  alias Nonprofiteer.Ingest.Run
  alias Nonprofiteer.Orgs.Address
  alias Nonprofiteer.Orgs.Organization

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"url" => url, "extract_id" => extract_id}}) do
    rows =
      url
      |> Client.fetch!()
      |> Bmf.parse!()

    {row_count, orphan_skipped} = import_rows(rows)

    record_run!(%{
      extract_id: extract_id,
      status: :success,
      row_count: row_count,
      orphan_skipped_count: orphan_skipped
    })

    :ok
  rescue
    error ->
      record_run!(%{
        extract_id: extract_id,
        status: :failure,
        error_message: Exception.message(error)
      })

      reraise error, __STACKTRACE__
  end

  # Upserts each parsed row, tallying successful upserts vs. EIN-less orphan skips.
  defp import_rows(rows) do
    Enum.reduce(rows, {0, 0}, fn
      %{org: %{ein: nil}}, {ok, orphan} ->
        {ok, orphan + 1}

      %{org: org_attrs, address: address_attrs}, {ok, orphan} ->
        org_attrs
        |> upsert_org!()
        |> link_address!(address_attrs)

        {ok + 1, orphan}
    end)
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
