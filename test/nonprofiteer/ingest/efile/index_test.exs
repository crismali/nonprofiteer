defmodule Nonprofiteer.Ingest.Efile.IndexTest do
  use ExUnit.Case, async: true

  alias Nonprofiteer.Ingest.Efile.Index

  defp sample, do: File.read!("test/fixtures/990/index_sample.csv")

  test "parses index rows into filing refs (known-answer)" do
    assert [first, second | _] = Index.parse!(sample())

    assert first == %{
             object_id: "202301529349200315",
             form_type: "990EZ",
             tax_year: 2022,
             filed_on: ~D[2023-06-01],
             xml_url:
               "https://gt990datalake-rawdata.s3.amazonaws.com/EfileData/XmlFiles/202301529349200315_public.xml"
           }

    assert second.form_type == "990"
    assert second.tax_year == 2018
    assert second.filed_on == ~D[2019-05-14]
  end

  test "returns all form types (worker applies the 990 + year filters)" do
    form_types =
      sample() |> Index.parse!() |> Enum.map(& &1.form_type) |> Enum.uniq() |> Enum.sort()

    assert form_types == ["990", "990EZ"]
  end

  test "raises LayoutError when a required column is missing" do
    [header | rows] = String.split(sample(), "\n", parts: 2)
    dropped = header |> String.replace("ObjectId,", "") |> then(&Enum.join([&1 | rows], "\n"))

    assert_raise Index.LayoutError, ~r/ObjectId/, fn -> Index.parse!(dropped) end
  end

  test "parse_stream yields the same refs as parse! from a chunked byte stream" do
    # Split the CSV into arbitrary byte chunks (mid-line, mid-field) to exercise the
    # line-reassembly across chunk boundaries.
    chunks = sample() |> chunk_bytes(17)

    streamed = chunks |> Index.parse_stream() |> Enum.to_list()

    assert streamed == Index.parse!(sample())
  end

  test "parse_stream is lazy — it doesn't parse past what's demanded" do
    # An infinite stream of blank chunks after the real data would hang a non-lazy parser.
    chunks = Stream.concat(chunk_bytes(sample(), 64), Stream.repeatedly(fn -> "" end))

    assert [first | _] = chunks |> Index.parse_stream() |> Enum.take(1)
    assert first.object_id == "202301529349200315"
  end

  test "parse_stream raises LayoutError on a missing column" do
    dropped = String.replace(sample(), "ObjectId,", "", global: false)

    assert_raise Index.LayoutError, ~r/ObjectId/, fn ->
      [dropped] |> Index.parse_stream() |> Enum.to_list()
    end
  end

  # Break a binary into `size`-byte chunks as a stream, mimicking an HTTP body.
  defp chunk_bytes(binary, size) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(size)
    |> Enum.map(&:binary.list_to_bin/1)
  end
end
