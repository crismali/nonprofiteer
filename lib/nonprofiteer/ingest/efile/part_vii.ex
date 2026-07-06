defmodule Nonprofiteer.Ingest.Efile.PartVii do
  @moduledoc """
  Parses a single 990 e-file return's XML into its filing header + Part VII Section A people.

  In-BEAM parse (Saxy) over the whole return — these files are small (KB–low-MB), so
  `Saxy.SimpleForm` (DOM) is used rather than a streaming handler; the multi-GB inputs that
  would need streaming are Phase-2 schedules, not this slice.

  **Phase-1 scope, enforced loudly (never silently):**

  - **Form 990 only.** 990-EZ / 990-PF carry their officers in different elements; those are a
    follow-up, so a non-990 return raises `UnsupportedReturnError` (the index worker filters them
    out first, so this is a defensive guard).
  - **Modern schema (2013+) only** — matches D9's ~3-year window. An older/unparseable version
    raises `UnsupportedReturnError`. The worker treats that as a counted skip, not a parse failure.

  Part VII Section A person groups carry no per-person address, so a person's D8 corroboration
  address is the **filer's business address** from the return header (also the org's address on
  that filing). Names/titles are kept **raw**; only the EIN is canonicalized.
  """
  alias Nonprofiteer.Ingest.Ein

  @min_schema_year 2013

  defmodule UnsupportedReturnError do
    @moduledoc "Raised when a return is out of Phase-1 scope (pre-2013 schema, or not Form 990)."
    defexception [:message]
    @type t :: %__MODULE__{message: String.t()}
  end

  @typedoc "One Part VII Section A listee — an individual or a business, with its listing order."
  @type person :: %{
          name: String.t(),
          title: String.t() | nil,
          part_vii_sequence: non_neg_integer()
        }

  @typedoc "The extracted return: filing header fields, filer address, and the Part VII people."
  @type parsed :: %{
          ein: String.t() | nil,
          return_type: :form_990,
          tax_year: integer() | nil,
          schema_version: String.t() | nil,
          address: map(),
          people: [person()]
        }

  @doc """
  Parses `xml` into a `t:parsed/0` map, or raises `UnsupportedReturnError` if the return is out of
  Phase-1 scope. Never returns an empty-people result for a supported return that clearly has
  officers — an unrecognized structure raises rather than silently under-extracting.
  """
  @spec parse!(binary()) :: parsed()
  def parse!(xml) when is_binary(xml) do
    tree =
      case xml |> strip_bom() |> Saxy.SimpleForm.parse_string() do
        {:ok, tree} ->
          tree

        {:error, error} ->
          raise UnsupportedReturnError, message: "unparseable XML: #{inspect(error)}"
      end

    version = attr(tree, "returnVersion")
    guard_schema!(version)

    header = child(tree, "ReturnHeader")
    filer = child(header, "Filer")

    %{
      ein: Ein.normalize(field(filer, "EIN")),
      return_type: return_type!(field(header, "ReturnTypeCd")),
      tax_year: tax_year(header),
      schema_version: version,
      address: filer_address(filer),
      people: people(tree)
    }
  end

  # Some IRS 990 XML files carry a leading UTF-8 byte-order mark, which Saxy rejects as an
  # unexpected token — strip it so a BOM'd-but-valid return parses instead of being silently
  # skipped as unparseable (caught by a known-answer fixture; see docs/EXAMPLES.md).
  defp strip_bom(<<0xEF, 0xBB, 0xBF>> <> rest), do: rest
  defp strip_bom(xml), do: xml

  defp guard_schema!(version) do
    year = schema_year(version)

    if is_nil(year) or year < @min_schema_year do
      raise UnsupportedReturnError, message: "unsupported schema version #{inspect(version)}"
    end
  end

  # "2020v4.0" -> 2020
  defp schema_year(nil), do: nil

  defp schema_year(version) do
    case Integer.parse(version) do
      {year, _rest} -> year
      :error -> nil
    end
  end

  defp return_type!("990"), do: :form_990

  defp return_type!(other) do
    raise UnsupportedReturnError, message: "Phase 1 supports Form 990 only, got #{inspect(other)}"
  end

  defp tax_year(header) do
    cond do
      txt = field(header, "TaxYr") -> to_int(txt)
      dt = field(header, "TaxPeriodEndDt") -> dt |> String.slice(0, 4) |> to_int()
      true -> nil
    end
  end

  defp to_int(txt) do
    case Integer.parse(txt) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp filer_address(filer) do
    address = child(filer, "USAddress")

    %{
      line1: field(address, "AddressLine1Txt"),
      line2: field(address, "AddressLine2Txt"),
      city: field(address, "CityNm"),
      region: field(address, "StateAbbreviationCd"),
      postal_code: field(address, "ZIPCd"),
      country: "US"
    }
  end

  defp people(tree) do
    tree
    |> child("ReturnData")
    |> child("IRS990")
    |> children_named("Form990PartVIISectionAGrp")
    |> Enum.with_index()
    |> Enum.map(fn {group, index} ->
      %{name: person_name(group), title: field(group, "TitleTxt"), part_vii_sequence: index}
    end)
    |> Enum.reject(&is_nil(&1.name))
  end

  # A listee is usually an individual (PersonNm); some are businesses (a management company).
  defp person_name(group) do
    field(group, "PersonNm") || group |> child("BusinessName") |> field("BusinessNameLine1Txt")
  end

  # --- Saxy SimpleForm navigation ({name, attributes, children}) ---

  defp attr(nil, _key), do: nil

  defp attr({_name, attributes, _children}, key) do
    Enum.find_value(attributes, fn {k, v} -> if k == key, do: v end)
  end

  defp child(nil, _name), do: nil

  defp child(node, name) do
    node |> child_nodes() |> Enum.find(&match?({^name, _, _}, &1))
  end

  defp children_named(nil, _name), do: []

  defp children_named(node, name) do
    node |> child_nodes() |> Enum.filter(&match?({^name, _, _}, &1))
  end

  defp child_nodes({_name, _attributes, children}), do: children

  # Text of a named child element, trimmed, blank normalized to nil.
  defp field(nil, _name), do: nil

  defp field(node, name) do
    case child(node, name) do
      nil -> nil
      element -> element |> text() |> blank_to_nil()
    end
  end

  defp text({_name, _attributes, children}) do
    children |> Enum.filter(&is_binary/1) |> Enum.join() |> String.trim()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
