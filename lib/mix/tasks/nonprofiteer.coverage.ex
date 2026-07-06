defmodule Mix.Tasks.Nonprofiteer.Coverage do
  @shortdoc "Prints data coverage/quality metrics for the ingested dataset"

  @moduledoc """
  Reports coverage and completeness metrics over the ingested data — the observable surface for
  catching silent ingest regressions the docs warn about (a run that "succeeds" but leaves the
  data thin). Complements the per-run `Ingest.Run` audit rows by measuring the *data itself*.

      mix nonprofiteer.coverage

  Prints, for the current database:

    * Organizations — total, and the share with an EIN, a linked address, and parsed Part VII
      people (the org spine's completeness + how far the 990 parse has reached).
    * Filings — total, and the share with at least one Part VII person.
    * People — total, and the share carrying an address and a title.
    * Ingest runs — per source: run count, last run time, and total rows / orphan skips.

  Boots the app (needs the DB). Read-only.
  """

  use Mix.Task

  require Ash.Query

  alias Nonprofiteer.Ingest.Run
  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Organization
  alias Nonprofiteer.Orgs.Person

  @requirements ["app.start"]

  @doc false
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(_args) do
    print_orgs()
    print_filings()
    print_people()
    print_runs()
    :ok
  end

  defp print_orgs do
    total = count(Organization)
    section("Organizations", total)
    metric("with EIN", count(Ash.Query.filter(Organization, not is_nil(ein))), total)
    metric("with address", count(Ash.Query.filter(Organization, not is_nil(address_id))), total)

    metric(
      "with Part VII people",
      count(Ash.Query.filter(Organization, exists(people, true))),
      total
    )
  end

  defp print_filings do
    total = count(Filing)
    section("Filings", total)
    metric("with Part VII people", count(Ash.Query.filter(Filing, exists(people, true))), total)
  end

  defp print_people do
    total = count(Person)
    section("People", total)
    metric("with address", count(Ash.Query.filter(Person, not is_nil(address_id))), total)
    metric("with title", count(Ash.Query.filter(Person, not is_nil(title))), total)
  end

  defp print_runs do
    runs = Ash.read!(Run)
    Mix.shell().info("\nIngest runs (#{length(runs)}):")

    runs
    |> Enum.group_by(& &1.source)
    |> Enum.sort_by(fn {source, _} -> to_string(source) end)
    |> Enum.each(fn {source, source_runs} ->
      last = source_runs |> Enum.map(& &1.inserted_at) |> Enum.max(DateTime)
      rows = source_runs |> Enum.map(& &1.row_count) |> Enum.sum()
      orphans = source_runs |> Enum.map(& &1.orphan_skipped_count) |> Enum.sum()

      Mix.shell().info(
        "  #{source}: #{length(source_runs)} runs, last #{DateTime.to_iso8601(last)}, " <>
          "#{rows} rows, #{orphans} orphan-skipped"
      )
    end)
  end

  defp count(query_or_resource), do: Ash.count!(query_or_resource)

  defp section(label, total), do: Mix.shell().info("\n#{label} (#{total}):")

  # `part/total`, one decimal; `n/a` when there's nothing to divide by (empty table).
  defp metric(label, part, total) do
    Mix.shell().info("  #{label}: #{part}/#{total} (#{pct(part, total)})")
  end

  defp pct(_part, 0), do: "n/a"
  defp pct(part, total), do: "#{Float.round(part / total * 100, 1)}%"
end
