defmodule Nonprofiteer.Ingest.BmfReconcileWorker do
  @moduledoc """
  Post-ingest pass that links group-exemption **subordinates** to their **central** org.

  Runs *after* the whole BMF fan-out has landed, and must be **global** — a central and its
  subordinates routinely sit in different state files (American Legion posts nationwide under a
  single Indiana central), so it can't run inside a per-state extract worker. Both a central
  (BMF `AFFILIATION` 6/8) and its subordinates (9) carry the same group number (`gen`); this
  pass builds a `gen → central` map from the centrals, then points each subordinate's
  `central_org_id` at its central.

  Idempotent: only writes when a subordinate's link actually changes, so a steady-state re-run
  is nearly write-free. Subordinates whose `gen` has no central in the dataset (central
  revoked, or not an EO filer) are counted as unresolved, not forced.
  """
  use Oban.Worker, queue: :ingest_bulk, max_attempts: 3

  require Ash.Query

  alias Nonprofiteer.Ingest.Run
  alias Nonprofiteer.Orgs.Organization

  # BMF AFFILIATION codes: 6 and 8 both denote a group ruling's central org; 9 is a subordinate.
  @central_codes ["6", "8"]
  @subordinate_code "9"

  # Tags this pass's `Ingest.Run` rows — distinct from the extract workers' state-code ids, so
  # reconcile runs are filterable in the audit log.
  @extract_id "reconcile"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    centrals = central_map()
    {linked, unresolved} = link_subordinates(centrals)

    record_run!(%{
      status: :success,
      row_count: linked,
      orphan_skipped_count: unresolved
    })

    :ok
  rescue
    error ->
      record_run!(%{status: :failure, error_message: Exception.message(error)})
      reraise error, __STACKTRACE__
  end

  # gen => central org id, for every BMF central that carries a group number.
  defp central_map do
    Organization
    |> Ash.Query.filter(source == :bmf and affiliation_code in ^@central_codes)
    |> Ash.Query.filter(not is_nil(gen))
    |> Ash.read!()
    |> Map.new(fn central -> {central.gen, central.id} end)
  end

  defp link_subordinates(centrals) do
    Organization
    |> Ash.Query.filter(source == :bmf and affiliation_code == ^@subordinate_code)
    |> Ash.Query.filter(not is_nil(gen))
    |> Ash.stream!()
    |> Enum.reduce({0, 0}, fn subordinate, {linked, unresolved} ->
      case Map.get(centrals, subordinate.gen) do
        # No central for this group in the dataset, or the "subordinate" is itself the central.
        nil -> {linked, unresolved + 1}
        central_id when central_id == subordinate.id -> {linked, unresolved + 1}
        central_id -> {linked + link!(subordinate, central_id), unresolved}
      end
    end)
  end

  # Returns 1 (a linked subordinate) whether or not a write was needed — the link exists either
  # way; the skip just avoids a redundant update on re-runs.
  defp link!(%Organization{central_org_id: central_id}, central_id), do: 1

  defp link!(subordinate, central_id) do
    subordinate
    |> Ash.Changeset.for_update(:update, %{central_org_id: central_id})
    |> Ash.update!()

    1
  end

  defp record_run!(attrs) do
    Run.record!(Map.merge(attrs, %{source: :bmf, extract_id: @extract_id}))
  end
end
