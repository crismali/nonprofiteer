defmodule Nonprofiteer.Ingest.Efile.IrsxCrosscheck do
  @moduledoc """
  Pure diff between our `Efile.PartVii` parse and ProPublica **IRSx** on the same return.

  IRSx (`jsfenfen/990-xml-reader`) is our offline reference validator (D14) — never in the
  pipeline. This module holds the two extractions and the comparison so they can be unit-tested
  without shelling out to Python; the `mix nonprofiteer.irsx_crosscheck` task is the thin IO
  wrapper that actually runs IRSx and feeds its JSON here.

  We only cross-check the overlap of the two parsers: Part VII Section A **listees**
  (name + title), in document order. IRSx names the group and its fields via its concordance
  (pinned below) — a rename upstream surfaces as an empty/short IRSx side in the diff rather
  than a silent pass.
  """
  alias Nonprofiteer.Ingest.Efile.PartVii

  # IRSx concordance names for Form 990 Part VII Section A (verified against irsx metadata):
  # the repeating group, the individual's name, a business listee's name, and the title.
  @irsx_group "Frm990PrtVIISctnA"
  @irsx_person_name "PrsnNm"
  @irsx_business_name "BsnssNmLn1Txt"
  @irsx_title "TtlTxt"

  @typedoc "One Part VII Section A listee reduced to the fields both parsers agree on."
  @type listee :: {name :: String.t(), title :: String.t() | nil}

  @typedoc """
  Result of a comparison: whether the two sides match, both listee lists, and the per-index
  disagreements (`{index, ours, theirs}`, with `nil` where one side ran short).
  """
  @type report :: %{
          match?: boolean(),
          ours: [listee()],
          theirs: [listee()],
          mismatches: [{non_neg_integer(), listee() | nil, listee() | nil}]
        }

  @doc "Our Part VII Section A listees for a return's XML, in listing order."
  @spec ours_from_xml(binary()) :: [listee()]
  def ours_from_xml(xml) when is_binary(xml) do
    xml
    |> PartVii.parse!()
    |> Map.fetch!(:people)
    |> Enum.map(&{&1.name, &1.title})
  end

  @doc """
  IRSx's Part VII Section A listees from one return's `irsx --schedule IRS990 --format json`
  output, in the order IRSx emits them. An absent group (schema drift, or a return with no
  Section A) yields `[]`, which the diff then reports against our side.
  """
  @spec theirs_from_json(binary()) :: [listee()]
  def theirs_from_json(json) when is_binary(json) do
    json
    |> Jason.decode!()
    |> irsx_group_rows()
    |> Enum.map(&{irsx_name(&1), blank_to_nil(&1[@irsx_title])})
  end

  @doc """
  Compares two ordered listee lists, pairing by index so an inserted/dropped row shows every
  later index as a mismatch (the honest signal that alignment broke, not just one cell).
  """
  @spec compare([listee()], [listee()]) :: report()
  def compare(ours, theirs) when is_list(ours) and is_list(theirs) do
    mismatches =
      Enum.reject(0..(max(length(ours), length(theirs)) - 1)//1, fn i ->
        Enum.at(ours, i) == Enum.at(theirs, i)
      end)
      |> Enum.map(&{&1, Enum.at(ours, &1), Enum.at(theirs, &1)})

    %{match?: mismatches == [], ours: ours, theirs: theirs, mismatches: mismatches}
  end

  @doc "Renders a `t:report/0` as a labelled, human-readable block for the task's output."
  @spec format_report(String.t(), report()) :: String.t()
  def format_report(label, %{match?: true, ours: ours}) do
    "✓ #{label}: #{length(ours)} Part VII Section A listees match IRSx"
  end

  def format_report(label, %{ours: ours, theirs: theirs, mismatches: mismatches}) do
    header =
      "✗ #{label}: ours=#{length(ours)} irsx=#{length(theirs)} " <>
        "(#{length(mismatches)} mismatch(es))"

    [header | Enum.map(mismatches, &format_mismatch/1)] |> Enum.join("\n")
  end

  defp format_mismatch({index, ours, theirs}) do
    "    [#{index}] ours=#{inspect(ours)} irsx=#{inspect(theirs)}"
  end

  # IRSx nests each schedule's repeating groups under `groups`; `--schedule IRS990` returns a
  # one-element list (the single IRS990 schedule) or an empty list if the return lacks it.
  defp irsx_group_rows(decoded) do
    case decoded do
      [%{"groups" => groups} | _] -> Map.get(groups, @irsx_group, [])
      _ -> []
    end
  end

  # Individuals carry `PrsnNm`; a business listee (management company) carries a business name.
  defp irsx_name(row) do
    blank_to_nil(row[@irsx_person_name]) || blank_to_nil(row[@irsx_business_name])
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
