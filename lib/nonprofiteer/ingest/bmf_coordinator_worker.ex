defmodule Nonprofiteer.Ingest.BmfCoordinatorWorker do
  @moduledoc """
  Monthly cron entry point for BMF ingest. Fans out one `BmfExtractWorker` per EO BMF extract
  rather than downloading and parsing everything inline — so one bad state file (or one slow
  download) can't fail the whole month.

  The extract list defaults to the IRS per-state EO BMF files but is overridable via
  `:nonprofiteer, :bmf_extracts` (used in tests to inject a stub extract).
  """
  use Oban.Worker, queue: :ingest_bulk, max_attempts: 3

  alias Nonprofiteer.Ingest.BmfExtractWorker

  @bmf_base_url "https://www.irs.gov/pub/irs-soi/"

  # The IRS publishes the EO BMF two ways: per-state files and 3 coarse regional files. We fan
  # out over the **per-state** set (verified live against irs.gov, 2026-07) — 50 states + DC +
  # Puerto Rico (`pr`) + international (`xx`) — so one bad state can't fail a whole region and
  # each run's `extract_id` is a meaningful state code.
  @state_codes ~w(
    al ak az ar ca co ct de fl ga hi id il in ia ks ky la me md ma mi mn ms mo mt ne nv nh nj
    nm ny nc nd oh ok or pa ri sc sd tn tx ut vt va wa wv wi wy dc pr xx
  )

  @default_extracts Enum.map(
                      @state_codes,
                      &%{id: &1, url: "#{@bmf_base_url}eo_#{&1}.csv"}
                    )

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    extracts()
    |> Enum.map(fn %{id: id, url: url} ->
      BmfExtractWorker.new(%{"extract_id" => id, "url" => url})
    end)
    |> Oban.insert_all()

    :ok
  end

  @doc "The BMF extracts to fan out over — the IRS per-state files unless overridden in config."
  @spec extracts :: [%{id: String.t(), url: String.t()}]
  def extracts, do: Application.get_env(:nonprofiteer, :bmf_extracts, @default_extracts)
end
