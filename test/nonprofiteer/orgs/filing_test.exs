defmodule Nonprofiteer.Orgs.FilingTest do
  use Nonprofiteer.DataCase, async: true

  import Nonprofiteer.OrgsFixtures

  alias Ash.Resource.Info
  alias Nonprofiteer.Orgs.Filing

  defp create_filing(attrs) do
    Filing
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  test "creates a filing linked to an organization" do
    org = create_org()

    filing =
      create_filing(%{
        organization_id: org.id,
        return_type: :form_990,
        tax_year: 2023,
        source_object_id: "202301234567890000"
      })

    assert filing.return_type == :form_990
    assert filing.tax_year == 2023
    assert filing.source_object_id == "202301234567890000"

    filing = Ash.load!(filing, :organization)
    assert filing.organization.id == org.id
  end

  test "organization is required" do
    assert {:error, %Ash.Error.Invalid{}} =
             Filing
             |> Ash.Changeset.for_create(:create, %{tax_year: 2023})
             |> Ash.create()
  end

  test "tax_year is required" do
    org = create_org()

    assert {:error, %Ash.Error.Invalid{}} =
             Filing
             |> Ash.Changeset.for_create(:create, %{organization_id: org.id})
             |> Ash.create()
  end

  test "return_type is constrained to the known forms" do
    org = create_org()

    assert {:error, %Ash.Error.Invalid{}} =
             Filing
             |> Ash.Changeset.for_create(:create, %{
               organization_id: org.id,
               tax_year: 2023,
               return_type: :form_1040
             })
             |> Ash.create()
  end

  test "an org can have multiple filings across years" do
    org = create_org()
    create_filing(%{organization_id: org.id, return_type: :form_990, tax_year: 2022})
    create_filing(%{organization_id: org.id, return_type: :form_990, tax_year: 2023})

    org = Ash.load!(org, :filings)
    assert length(org.filings) == 2
  end

  test "an amendment supersedes the prior filing (D10)" do
    org = create_org()
    original = create_filing(%{organization_id: org.id, return_type: :form_990, tax_year: 2023})
    amended = create_filing(%{organization_id: org.id, return_type: :form_990, tax_year: 2023})

    original =
      original
      |> Ash.Changeset.for_update(:update, %{superseded_by_id: amended.id})
      |> Ash.update!()
      |> Ash.load!(:superseded_by)

    assert original.superseded_by.id == amended.id
  end

  test "tombstone soft-deletes without destroying history (D10)" do
    org = create_org()
    filing = create_filing(%{organization_id: org.id, return_type: :form_990, tax_year: 2023})

    tombstoned =
      filing
      |> Ash.Changeset.for_update(:tombstone, %{})
      |> Ash.update!()

    refute is_nil(tombstoned.tombstoned_at)
    assert length(Ash.read!(Filing)) == 1
  end

  test "has no hard destroy action (D10)" do
    refute :destroy in (Filing |> Info.actions() |> Enum.map(& &1.name))
  end
end
