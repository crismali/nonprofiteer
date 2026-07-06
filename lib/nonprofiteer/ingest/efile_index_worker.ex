defmodule Nonprofiteer.Ingest.EfileIndexWorker do
  @moduledoc """
  Monthly cron entry for the 990 e-file ingest. Downloads the GivingTuesday Data Lake index,
  filters to in-scope filings, and fans out one `EfileParseWorker` per new return.

  In scope = **Form 990** (990-EZ/990-PF are a follow-up) with a `tax_year` at or after the
  D9 window cutoff, whose `source_object_id` isn't already a `Filing`. The first run backfills
  the whole window; later runs are incremental (the index is a full snapshot each time, so
  "new" is decided by diffing against ingested filings — same shape as the BMF full-universe
  ingest). One `Ingest.Run` records the pass (candidates seen vs. enqueued).

  The index URL defaults to the latest dated snapshot (discovered by listing the bucket), or
  `:nonprofiteer, :efile_index_url` when set (tests inject a small stub). The tax-year cutoff
  defaults from the current year but can be overridden per-job (`"min_tax_year"`) or via
  `:nonprofiteer, :efile_min_tax_year`.

  The index is **streamed** (`Client.stream!` + `Index.parse_stream`) and processed in batches,
  so the all-years national corpus is never held whole in memory; the already-ingested diff is
  narrowed to each batch's object ids (a single `IN (...)` per batch) rather than loading every
  ingested id up front.
  """
  use Oban.Worker, queue: :ingest_incremental, max_attempts: 3

  require Ash.Query

  alias Nonprofiteer.Ingest.Client
  alias Nonprofiteer.Ingest.Efile.Index
  alias Nonprofiteer.Ingest.EfileParseWorker
  alias Nonprofiteer.Ingest.Run
  alias Nonprofiteer.Orgs.Filing

  @form_990 "990"
  @index_bucket_url "https://gt990datalake-rawdata.s3.amazonaws.com"
  @index_prefix "Indices/990xmls/"

  # In-scope candidates are diffed + enqueued a batch at a time so memory stays bounded no
  # matter how large the index is.
  @batch_size 1_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    min_tax_year = args["min_tax_year"] || default_min_tax_year()

    {candidate_count, enqueued_count} =
      index_url()
      |> Client.stream!()
      |> Index.parse_stream()
      |> Stream.filter(&in_scope?(&1, min_tax_year))
      |> Stream.chunk_every(@batch_size)
      |> Enum.reduce({0, 0}, fn batch, {seen, enqueued} ->
        new_refs = reject_already_ingested(batch)
        enqueue(new_refs)
        {seen + length(batch), enqueued + length(new_refs)}
      end)

    record_run!(candidate_count, enqueued_count)

    :ok
  end

  defp in_scope?(ref, min_tax_year) do
    ref.form_type == @form_990 and is_integer(ref.tax_year) and ref.tax_year >= min_tax_year and
      is_binary(ref.object_id) and is_binary(ref.xml_url)
  end

  # Diff this batch against filings we already have. Narrowed to the batch's object ids (one
  # `IN (...)` query), so memory doesn't grow with the ingested corpus.
  defp reject_already_ingested(refs) do
    object_ids = Enum.map(refs, & &1.object_id)

    ingested =
      Filing
      |> Ash.Query.filter(source_object_id in ^object_ids)
      |> Ash.read!()
      |> MapSet.new(& &1.source_object_id)

    Enum.reject(refs, &MapSet.member?(ingested, &1.object_id))
  end

  defp enqueue(refs) do
    refs
    |> Enum.map(fn ref ->
      EfileParseWorker.new(%{
        "object_id" => ref.object_id,
        "xml_url" => ref.xml_url,
        "filed_on" => ref.filed_on && Date.to_iso8601(ref.filed_on)
      })
    end)
    |> Oban.insert_all()
  end

  defp record_run!(candidate_count, enqueued_count) do
    Run.record!(%{
      source: :efile_990,
      extract_id: "index",
      status: :success,
      row_count: enqueued_count,
      orphan_skipped_count: candidate_count - enqueued_count
    })
  end

  @doc "The index CSV URL — the configured override, else the latest dated snapshot in the bucket."
  @spec index_url() :: String.t()
  def index_url do
    case Application.get_env(:nonprofiteer, :efile_index_url) do
      nil -> discover_latest_index_url()
      url -> url
    end
  end

  # Lists the index prefix and picks the newest `..._created_on_YYYY-MM-DD.csv` snapshot.
  defp discover_latest_index_url do
    key =
      "#{@index_bucket_url}/?list-type=2&prefix=#{URI.encode(@index_prefix)}"
      |> Client.fetch!()
      |> latest_csv_key()

    "#{@index_bucket_url}/#{key}"
  end

  defp latest_csv_key(list_xml) do
    ~r{<Key>([^<]*\.csv)</Key>}
    |> Regex.scan(list_xml)
    |> Enum.map(fn [_, key] -> key end)
    |> Enum.max()
  end

  @doc "Default tax-year cutoff — the D9 ~3-filing-year window off the current year."
  @spec default_min_tax_year() :: integer()
  def default_min_tax_year do
    Application.get_env(:nonprofiteer, :efile_min_tax_year, Date.utc_today().year - 4)
  end
end
