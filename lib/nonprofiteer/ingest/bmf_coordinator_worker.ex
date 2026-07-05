defmodule Nonprofiteer.Ingest.BmfCoordinatorWorker do
  @moduledoc """
  Monthly cron entry point for BMF ingest. Fans out one `BmfExtractWorker` per EO BMF extract
  rather than downloading and parsing everything inline — so one bad regional file (or one
  slow download) can't fail the whole month.

  The extract list defaults to the IRS regional EO BMF files but is overridable via
  `:nonprofiteer, :bmf_extracts` (used in tests to inject a stub extract).
  """
  use Oban.Worker, queue: :ingest_bulk, max_attempts: 3

  alias Nonprofiteer.Ingest.BmfExtractWorker

  # IRS EO BMF regional extracts. These cover all states + DC + PR + international between them.
  # NOTE: confirm the current published file set against irs.gov before relying on this in
  # production — the IRS has changed the split (per-state vs. regional) over time.
  @default_extracts [
    %{id: "eo1", url: "https://www.irs.gov/pub/irs-soi/eo1.csv"},
    %{id: "eo2", url: "https://www.irs.gov/pub/irs-soi/eo2.csv"},
    %{id: "eo3", url: "https://www.irs.gov/pub/irs-soi/eo3.csv"},
    %{id: "eo4", url: "https://www.irs.gov/pub/irs-soi/eo4.csv"}
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    extracts()
    |> Enum.map(fn %{id: id, url: url} ->
      BmfExtractWorker.new(%{"extract_id" => id, "url" => url})
    end)
    |> Oban.insert_all()

    :ok
  end

  @doc "The BMF extracts to fan out over — the IRS regional files unless overridden in config."
  @spec extracts :: [%{id: String.t(), url: String.t()}]
  def extracts, do: Application.get_env(:nonprofiteer, :bmf_extracts, @default_extracts)
end
