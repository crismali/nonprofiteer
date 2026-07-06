NimbleCSV.define(Nonprofiteer.Ingest.Efile.Index.Csv, separator: ",", escape: "\"")

defmodule Nonprofiteer.Ingest.Efile.Index do
  @moduledoc """
  Parses a GivingTuesday Data Lake index (`Indices/990xmls/index_all_years_...csv`) into filing
  refs the parse pipeline fans out over.

  Each ref carries only the **index-authoritative** fields — the discovery pointer
  (`object_id`, `xml_url`), the `filed_on` date, and the `form_type`/`tax_year` used to filter
  *before* downloading a return. The return's own EIN, schema version, tax year, address, and
  people come from parsing the XML (`Efile.PartVii`), which is authoritative for those.

  Columns are matched by **header name**, not fixed position — the index is a rich, evolving
  dataset, so we pin only the handful of columns we use (raising if one goes missing) rather
  than the whole 35-column layout.
  """
  alias Nonprofiteer.Ingest.Efile.Index.Csv

  # Header names we depend on. `LayoutError` fires if any is absent — a loud guard against the
  # index dropping/renaming a column we rely on.
  @object_id "ObjectId"
  @form_type "FormType"
  @tax_year "TaxYear"
  @submitted_on "SubmittedOn"
  @url "URL"
  @required [@object_id, @form_type, @tax_year, @submitted_on, @url]

  defmodule LayoutError do
    @moduledoc "Raised when the index is missing a column the parser depends on."
    defexception [:message]
    @type t :: %__MODULE__{message: String.t()}
  end

  @typedoc "One filing's index metadata — enough to filter, then fetch and parse the XML."
  @type ref :: %{
          object_id: String.t(),
          form_type: String.t() | nil,
          tax_year: integer() | nil,
          filed_on: Date.t() | nil,
          xml_url: String.t() | nil
        }

  @doc """
  Parses an index CSV into filing refs, in file order. Raises `LayoutError` if a required
  column is missing. Returns **all** rows (all form types/years) — the worker applies the
  Form-990 and D9 year filters.
  """
  @spec parse!(binary()) :: [ref()]
  def parse!(csv) when is_binary(csv) do
    [header | rows] = Csv.parse_string(csv, skip_headers: false)
    column = column_index!(header)

    Enum.map(rows, &ref(&1, column))
  end

  @doc """
  Lazily parses an index CSV *stream* — an enumerable of binary chunks (see `Client.stream!/1`)
  — into a stream of filing refs, so the whole index isn't held in memory. Resolves columns
  from the first (header) row, then emits a ref per data row. Raises `LayoutError` (during
  consumption) if a required column is missing.
  """
  @spec parse_stream(Enumerable.t()) :: Enumerable.t()
  def parse_stream(chunks) do
    chunks
    |> to_lines()
    |> Csv.parse_stream(skip_headers: false)
    |> Stream.transform(:awaiting_header, fn
      header, :awaiting_header -> {[], column_index!(header)}
      row, column -> {[ref(row, column)], column}
    end)
  end

  # Re-chunk an arbitrary byte stream (HTTP delivers whatever-sized chunks) into newline-
  # terminated lines, the shape `NimbleCSV.parse_stream/2` expects. A partial trailing line is
  # buffered until the next chunk completes it; a newline inside a quoted field is safe — it
  # lands mid-line and `parse_stream` reassembles across elements on the open quote.
  defp to_lines(chunks) do
    Stream.transform(
      chunks,
      fn -> "" end,
      fn chunk, buffer ->
        parts = String.split(buffer <> chunk, "\n")
        {complete, [rest]} = Enum.split(parts, -1)
        {Enum.map(complete, &(&1 <> "\n")), rest}
      end,
      fn buffer -> {if(buffer == "", do: [], else: [buffer]), ""} end
    )
  end

  defp ref(row, column) do
    %{
      object_id: cell(row, column, @object_id),
      form_type: cell(row, column, @form_type),
      tax_year: cell(row, column, @tax_year) |> to_int(),
      filed_on: cell(row, column, @submitted_on) |> to_date(),
      xml_url: cell(row, column, @url)
    }
  end

  defp column_index!(header) do
    trimmed = Enum.map(header, &String.trim/1)
    index = trimmed |> Enum.with_index() |> Map.new()

    case Enum.reject(@required, &Map.has_key?(index, &1)) do
      [] ->
        index

      missing ->
        raise LayoutError, message: "index missing required column(s): #{inspect(missing)}"
    end
  end

  defp cell(row, column, name) do
    row |> Enum.at(Map.fetch!(column, name)) |> blank_to_nil()
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp to_int(nil), do: nil

  defp to_int(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp to_date(nil), do: nil

  defp to_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end
end
