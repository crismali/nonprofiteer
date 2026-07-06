defmodule Nonprofiteer.Ingest.EfileSupersedeWorker do
  @moduledoc """
  Marks amended 990 filings as superseding their predecessors (D10/D15).

  A filing amendment arrives as a **distinct** `Filing` (its own Data Lake OBJECT_ID), so within
  each `(organization, tax_year, return_type)` group the latest by `filed_on` is canonical and
  the earlier ones get `superseded_by` pointed at it — **both kept**, never overwritten. Runs as
  a global post-parse pass (a filing and its amendment can land in different parse jobs), the day
  after the e-file ingest, mirroring the GEN reconcile.

  Composes with the sync feed for free (D16): setting `superseded_by` bumps the row's
  `updated_at`, so the superseded filing re-emits with `event_type: :superseded`. Idempotent —
  only writes when a link actually changes.

  > Scale follow-up: loads non-tombstoned filings to group them — fine at Phase-1 volume; narrow
  > to groups with >1 filing before this runs against the full national corpus.
  """
  use Oban.Worker, queue: :ingest_incremental, max_attempts: 3

  require Ash.Query

  alias Nonprofiteer.Orgs.Filing

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Filing
    |> Ash.Query.filter(is_nil(tombstoned_at))
    |> Ash.read!()
    |> Enum.group_by(&{&1.organization_id, &1.tax_year, &1.return_type})
    |> Enum.each(&reconcile_group/1)

    :ok
  end

  defp reconcile_group({_key, [_only_one]}), do: :ok

  defp reconcile_group({_key, filings}) do
    canonical = Enum.max_by(filings, &filed_on_key/1)

    Enum.each(filings, fn filing ->
      cond do
        filing.id == canonical.id -> ensure_not_superseded(filing)
        filing.superseded_by_id != canonical.id -> set_superseded(filing, canonical.id)
        true -> :ok
      end
    end)
  end

  # Sortable key: any dated filing beats an undated one; among dated, the latest wins.
  defp filed_on_key(%{filed_on: nil}), do: {0, 0}
  defp filed_on_key(%{filed_on: date}), do: {1, Date.to_gregorian_days(date)}

  defp ensure_not_superseded(%{superseded_by_id: nil}), do: :ok

  defp ensure_not_superseded(filing) do
    filing |> Ash.Changeset.for_update(:update, %{superseded_by_id: nil}) |> Ash.update!()
  end

  defp set_superseded(filing, canonical_id) do
    filing
    |> Ash.Changeset.for_update(:update, %{superseded_by_id: canonical_id})
    |> Ash.update!()
  end
end
