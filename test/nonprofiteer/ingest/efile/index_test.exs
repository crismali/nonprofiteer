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
end
