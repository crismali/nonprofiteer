defmodule Mix.Tasks.Nonprofiteer.IrsxCrosscheck do
  @shortdoc "Diff our Part VII parse against ProPublica IRSx on the known-answer fixtures"

  @moduledoc """
  Dev-time cross-check of `Efile.PartVii` against **IRSx** (`jsfenfen/990-xml-reader`), our
  offline reference validator (D14). **Not run in CI** — it needs a Python IRSx install:

      pip install irsx
      mix nonprofiteer.irsx_crosscheck

  For each real-return fixture it parses Part VII Section A both ways and diffs the listees
  (name + title, in order). A clean run is the evidence our in-BEAM parse matches the reference;
  a mismatch exits non-zero so an intentional run fails loud. If `irsx` isn't on `PATH` the task
  prints install guidance and stops without failing (it's an optional dev dependency).

  IRSx downloads returns by OBJECT_ID, so each fixture is seeded into a throwaway IRSx cache
  (`IRSX_CACHE_DIRECTORY/XML/<object_id>_public.xml`) to keep the run fully offline. Comparison
  + JSON/XML extraction live in `Nonprofiteer.Ingest.Efile.IrsxCrosscheck` (unit-tested there).
  """
  use Mix.Task

  alias Nonprofiteer.Ingest.Efile.IrsxCrosscheck

  # The real returns behind the known-answer validation carry OBJECT_IDs (see the capture task),
  # so they double as IRSx cross-check cases. Slug → its committed 990 XML + Data Lake OBJECT_ID.
  @cases [
    %{slug: "american_action_network", object_id: "202201369349304100"},
    %{slug: "american_action_forum", object_id: "202311359349309026"}
  ]

  @fixtures "test/fixtures/known_answers"

  @impl Mix.Task
  def run(_args) do
    if System.find_executable("irsx") do
      run_crosscheck()
    else
      Mix.shell().info("""
      irsx not found on PATH — this dev-time cross-check needs ProPublica's IRSx:

          pip install irsx

      Skipping (IRSx is an optional dev dependency, never part of the pipeline or CI).
      """)
    end
  end

  defp run_crosscheck do
    reports = Enum.map(@cases, &crosscheck_case/1)

    Enum.each(reports, fn {slug, report} ->
      Mix.shell().info(IrsxCrosscheck.format_report(slug, report))
    end)

    if Enum.any?(reports, fn {_slug, report} -> not report.match? end) do
      Mix.raise("IRSx cross-check found mismatches — see the diff above.")
    end
  end

  defp crosscheck_case(%{slug: slug, object_id: object_id}) do
    xml = File.read!(Path.join(@fixtures, "#{slug}_990.xml"))
    ours = IrsxCrosscheck.ours_from_xml(xml)
    theirs = IrsxCrosscheck.theirs_from_json(run_irsx(object_id, xml))

    {slug, IrsxCrosscheck.compare(ours, theirs)}
  end

  # Runs IRSx against a fixture without hitting the network: seed a temp cache with the XML under
  # the OBJECT_ID IRSx expects, then ask only for the IRS990 schedule as JSON.
  defp run_irsx(object_id, xml) do
    cache = Path.join(System.tmp_dir!(), "irsx_crosscheck_#{object_id}")
    File.mkdir_p!(Path.join(cache, "XML"))
    File.write!(Path.join([cache, "XML", "#{object_id}_public.xml"]), xml)

    {json, 0} =
      System.cmd("irsx", ["--schedule", "IRS990", "--format", "json", object_id],
        env: [{"IRSX_CACHE_DIRECTORY", cache}]
      )

    json
  end
end
