NimbleCSV.define(Nonprofiteer.Ingest.Bmf.Csv, separator: ",", escape: "\"")

defmodule Nonprofiteer.Ingest.Bmf do
  @moduledoc """
  Parser for an IRS EO Business Master File (BMF) extract — the org spine, no XML.

  The single biggest ingest risk is a *silent* parse failure from upstream column drift, so
  the parser **pins the exact expected header** and raises `LayoutError` before mapping any
  row. A reordered/renamed/added column fails the whole run loudly rather than quietly writing
  a street address into the NTEE field. The known-answer fixtures under `test/fixtures/bmf/`
  are the second guard; keep them captured from real IRS files.

  Output is source-shaped, not persisted here — each row becomes
  `%{org: org_attrs, address: address_attrs}`; the worker is what upserts through Ash actions.
  """
  alias Nonprofiteer.Ingest.Bmf.Csv
  alias Nonprofiteer.Ingest.Ein

  # The canonical EO BMF extract layout, in order. Pinned so drift raises. If the IRS revises
  # this, update the list *and* re-capture the fixtures in the same change — never loosen the
  # assertion to make a run pass.
  @expected_headers ~w(
    EIN NAME ICO STREET CITY STATE ZIP GROUP SUBSECTION AFFILIATION CLASSIFICATION RULING
    DEDUCTIBILITY FOUNDATION ACTIVITY ORGANIZATION STATUS TAX_PERIOD ASSET_CD INCOME_CD
    FILING_REQ_CD PF_FILING_REQ_CD ACCT_PD ASSET_AMT INCOME_AMT REVENUE_AMT NTEE_CD SORT_NAME
  )

  # Column positions we actually map into the spine (Phase 1: identity, address, NTEE, group,
  # affiliation). AFFILIATION distinguishes a group's central org (6/8) from its subordinates
  # (9) — both share the same GROUP number — so it's required for the later GEN→central
  # reconcile, not just decoration.
  @col %{
    ein: 0,
    name: 1,
    street: 3,
    city: 4,
    state: 5,
    zip: 6,
    group: 7,
    affiliation: 9,
    ntee: 26
  }

  # The EO BMF is a US-domestic registry (the `xx` extract is US orgs operating abroad, still
  # filed with the IRS), so every address defaults to US; there is no country column to read.
  @default_country "US"

  defmodule LayoutError do
    @moduledoc "Raised when a BMF extract's header doesn't match the pinned expected layout."
    defexception [:message]
    @type t :: %__MODULE__{message: String.t()}
  end

  @doc """
  Parses a BMF extract (CSV string) into a list of `%{org: ..., address: ...}` attribute maps.

  Raises `LayoutError` if the header row doesn't exactly match the pinned expected layout.
  """
  @spec parse!(binary()) :: [%{org: map(), address: map()}]
  def parse!(csv) when is_binary(csv) do
    [headers | rows] = Csv.parse_string(csv, skip_headers: false)

    assert_layout!(headers)

    Enum.map(rows, &row_to_attrs/1)
  end

  defp assert_layout!(headers) do
    trimmed = Enum.map(headers, &String.trim/1)

    if trimmed != @expected_headers do
      raise LayoutError,
        message:
          "BMF header drift: expected #{inspect(@expected_headers)}, got #{inspect(trimmed)}"
    end

    :ok
  end

  defp row_to_attrs(row) do
    %{
      org: %{
        ein: Ein.normalize(at(row, @col.ein)),
        name: at(row, @col.name),
        ntee_code: at(row, @col.ntee),
        gen: group_to_gen(at(row, @col.group)),
        affiliation_code: at(row, @col.affiliation)
      },
      address: %{
        line1: at(row, @col.street),
        city: at(row, @col.city),
        region: at(row, @col.state),
        postal_code: at(row, @col.zip),
        country: @default_country
      }
    }
  end

  # Cell value, trimmed, with blanks normalized to nil.
  defp at(row, index) do
    row
    |> Enum.at(index)
    |> blank_to_nil()
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # A GROUP of "0000" (or all-zero) means "no group exemption" in the BMF — treat as nil.
  defp group_to_gen(nil), do: nil

  defp group_to_gen(group) do
    if String.to_integer(group) == 0, do: nil, else: group
  rescue
    ArgumentError -> group
  end
end
