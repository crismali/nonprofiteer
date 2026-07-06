defmodule Mix.Tasks.Nonprofiteer.CoverageTest do
  use Nonprofiteer.DataCase, async: true

  import ExUnit.CaptureIO
  import Nonprofiteer.OrgsFixtures

  alias Mix.Tasks.Nonprofiteer.Coverage
  alias Nonprofiteer.Ingest.Run
  alias Nonprofiteer.Orgs.Address
  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Person

  defp create!(resource, attrs) do
    resource |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  test "reports org/filing/people coverage percentages and per-source runs" do
    # A fully-populated org: EIN, linked address, a filing, and a Part VII person.
    address = create!(Address, %{line1: "1 Main St"})

    org =
      %{name: "Full Org", ein: "123456789"}
      |> create_org()
      |> Ash.Changeset.for_update(:update, %{address_id: address.id})
      |> Ash.update!()

    filing = create!(Filing, %{organization_id: org.id, return_type: :form_990, tax_year: 2023})
    create!(Person, %{organization_id: org.id, filing_id: filing.id, name: "Jane", title: "PRES"})

    # A sparse org: no EIN, no address, no people.
    create_org(%{name: "Sparse Org"})

    Run.record!(%{
      source: :bmf,
      extract_id: "CA",
      status: :success,
      row_count: 3,
      orphan_skipped_count: 1
    })

    output = capture_io(fn -> Coverage.run([]) end)

    assert output =~ "Organizations (2):"
    assert output =~ "with EIN: 1/2 (50.0%)"
    assert output =~ "with address: 1/2 (50.0%)"
    assert output =~ "with Part VII people: 1/2 (50.0%)"

    assert output =~ "Filings (1):"
    assert output =~ "with Part VII people: 1/1 (100.0%)"

    assert output =~ "People (1):"
    assert output =~ "with title: 1/1 (100.0%)"

    assert output =~ "Ingest runs (1):"
    assert output =~ "bmf: 1 runs"
    assert output =~ "3 rows, 1 orphan-skipped"
  end

  test "handles an empty dataset without dividing by zero" do
    output = capture_io(fn -> Coverage.run([]) end)

    assert output =~ "Organizations (0):"
    assert output =~ "with EIN: 0/0 (n/a)"
    assert output =~ "Ingest runs (0):"
  end
end
