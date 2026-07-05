defmodule Nonprofiteer.Orgs.PersonTest do
  use Nonprofiteer.DataCase, async: true

  alias Ash.Resource.Info
  alias Nonprofiteer.Orgs.Address
  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Organization
  alias Nonprofiteer.Orgs.Person

  defp fixtures do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "ACME Foundation", ein: "123456789"})
      |> Ash.create!()

    filing =
      Filing
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        return_type: :form_990,
        tax_year: 2023
      })
      |> Ash.create!()

    %{org: org, filing: filing}
  end

  defp create_person(attrs) do
    Person
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  test "creates a Part VII person carrying org + source-filing pointer (D8)" do
    %{org: org, filing: filing} = fixtures()

    person =
      create_person(%{
        organization_id: org.id,
        filing_id: filing.id,
        name: "Jane Director",
        title: "PRESIDENT"
      })

    assert person.name == "Jane Director"
    assert person.title == "PRESIDENT"

    person = Ash.load!(person, [:organization, :filing])
    assert person.organization.id == org.id
    assert person.filing.id == filing.id
  end

  test "name is required" do
    %{org: org, filing: filing} = fixtures()

    assert {:error, %Ash.Error.Invalid{}} =
             Person
             |> Ash.Changeset.for_create(:create, %{organization_id: org.id, filing_id: filing.id})
             |> Ash.create()
  end

  test "source-filing pointer (filing) is required (D8)" do
    %{org: org} = fixtures()

    assert {:error, %Ash.Error.Invalid{}} =
             Person
             |> Ash.Changeset.for_create(:create, %{organization_id: org.id, name: "No Filing"})
             |> Ash.create()
  end

  test "carries an associated address (D8 corroboration)" do
    %{org: org, filing: filing} = fixtures()

    address =
      Address
      |> Ash.Changeset.for_create(:create, %{line1: "1 Main St", city: "Springfield"})
      |> Ash.create!()

    person =
      create_person(%{
        organization_id: org.id,
        filing_id: filing.id,
        name: "Jane Director",
        address_id: address.id
      })

    person = Ash.load!(person, :address)
    assert person.address.id == address.id
  end

  test "people are reachable from both the org and the filing" do
    %{org: org, filing: filing} = fixtures()
    create_person(%{organization_id: org.id, filing_id: filing.id, name: "Officer One"})
    create_person(%{organization_id: org.id, filing_id: filing.id, name: "Officer Two"})

    assert length(Ash.load!(org, :people).people) == 2
    assert length(Ash.load!(filing, :people).people) == 2
  end

  test "tombstone soft-deletes without destroying history (D10)" do
    %{org: org, filing: filing} = fixtures()
    person = create_person(%{organization_id: org.id, filing_id: filing.id, name: "Withdrawn"})

    tombstoned =
      person
      |> Ash.Changeset.for_update(:tombstone, %{})
      |> Ash.update!()

    refute is_nil(tombstoned.tombstoned_at)
    assert length(Ash.read!(Person)) == 1
  end

  test "has no hard destroy action (D10)" do
    refute :destroy in (Person |> Info.actions() |> Enum.map(& &1.name))
  end
end
