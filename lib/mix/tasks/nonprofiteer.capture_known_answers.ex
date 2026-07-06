defmodule Mix.Tasks.Nonprofiteer.CaptureKnownAnswers do
  @shortdoc "Re-capture the known-answer validation fixtures from live IRS sources"

  @moduledoc """
  Captures the real IRS source data behind the known-answer validation (see docs/EXAMPLES.md)
  into `test/fixtures/known_answers/` — the 990 XML for each case's return plus the case's BMF
  row. Run it to refresh the fixtures and **diff the result**: a diff is how upstream schema or
  column drift gets caught deliberately, rather than only when a production job breaks.

      mix nonprofiteer.capture_known_answers

  The case list is pinned below (EIN + Data Lake OBJECT_ID). Adding a case means finding its
  latest Form 990 OBJECT_ID — grep the Data Lake index
  (`Indices/990xmls/index_all_years_...csv`) for the EIN — then documenting the bridge in
  docs/EXAMPLES.md.
  """
  use Mix.Task

  alias Nonprofiteer.Ingest.Client

  @fixtures "test/fixtures/known_answers"
  @xml_base "https://gt990datalake-rawdata.s3.amazonaws.com/EfileData/XmlFiles"
  @bmf_base "https://www.irs.gov/pub/irs-soi"

  # Each case: the nonprofit's EIN, its BMF state extract, the return's Data Lake OBJECT_ID, and
  # the fixture slug. Bridge details live in docs/EXAMPLES.md.
  @cases [
    %{
      ein: "270730508",
      state: "dc",
      object_id: "202201369349304100",
      slug: "american_action_network"
    },
    %{
      ein: "270567765",
      state: "dc",
      object_id: "202311359349309026",
      slug: "american_action_forum"
    }
  ]

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:req)
    File.mkdir_p!(@fixtures)
    capture_returns()
    capture_bmf_rows()
  end

  defp capture_returns do
    Enum.each(@cases, fn %{object_id: object_id, slug: slug} ->
      xml = Client.fetch!("#{@xml_base}/#{object_id}_public.xml")
      path = Path.join(@fixtures, "#{slug}_990.xml")
      File.write!(path, xml)
      Mix.shell().info("captured #{path}")
    end)
  end

  # One state extract per state, grepping every case EIN in that state out of it.
  defp capture_bmf_rows do
    @cases
    |> Enum.group_by(& &1.state)
    |> Enum.each(fn {state, cases} ->
      [header | rows] = "#{@bmf_base}/eo_#{state}.csv" |> Client.fetch!() |> String.split("\n")
      eins = MapSet.new(cases, & &1.ein)
      matched = Enum.filter(rows, &MapSet.member?(eins, &1 |> String.split(",") |> List.first()))

      path = Path.join(@fixtures, "bmf_#{state}_known.csv")
      File.write!(path, Enum.join([header | matched], "\n") <> "\n")
      Mix.shell().info("captured #{path} (#{length(matched)} rows)")
    end)
  end
end
