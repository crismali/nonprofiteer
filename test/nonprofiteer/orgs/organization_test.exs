defmodule Nonprofiteer.Orgs.OrganizationTest do
  use Nonprofiteer.DataCase, async: true

  import Nonprofiteer.OrgsFixtures

  alias Ash.Resource.Info
  alias Nonprofiteer.Orgs.Address
  alias Nonprofiteer.Orgs.Organization

  test "creates an organization with a name and EIN" do
    org = create_org(%{name: "ACME Foundation", ein: "123456789"})

    assert org.name == "ACME Foundation"
    assert org.ein == "123456789"
    assert is_nil(org.tombstoned_at)
  end

  test "name is required" do
    assert {:error, %Ash.Error.Invalid{}} =
             Organization
             |> Ash.Changeset.for_create(:create, %{ein: "123456789"})
             |> Ash.create()
  end

  test "EIN is not unique — cardinality 0/1/many (D7)" do
    # Two distinct orgs can share an EIN (group exemptions, subchapters), and an org can have
    # no EIN at all. All three must be allowed.
    create_org(%{name: "Central Org", ein: "111111111"})
    create_org(%{name: "Subordinate Org", ein: "111111111"})
    create_org(%{name: "EIN-less Org"})

    assert length(Ash.read!(Organization)) == 3
  end

  test "models central-vs-subordinate structure explicitly (D7)" do
    central = create_org(%{name: "Central", ein: "222222222"})
    sub = create_org(%{name: "Subordinate", central_org_id: central.id})

    sub = Ash.load!(sub, :central_org)
    assert sub.central_org.id == central.id

    central = Ash.load!(central, :subordinates)
    assert Enum.map(central.subordinates, & &1.id) == [sub.id]
  end

  test "attaches a shared address (D8 corroboration)" do
    address =
      Address
      |> Ash.Changeset.for_create(:create, %{line1: "1 Main St", city: "Springfield"})
      |> Ash.create!()

    org = create_org(%{name: "Housed Org", address_id: address.id})

    org = Ash.load!(org, :address)
    assert org.address.id == address.id
  end

  test "tombstone soft-deletes without destroying history (D10)" do
    org = create_org(%{name: "Withdrawn Org"})

    tombstoned =
      org
      |> Ash.Changeset.for_update(:tombstone, %{})
      |> Ash.update!()

    refute is_nil(tombstoned.tombstoned_at)
    # Still readable — soft delete, not a hard destroy.
    assert length(Ash.read!(Organization)) == 1
  end

  test "has no hard destroy action (D10)" do
    action_names = Organization |> Info.actions() |> Enum.map(& &1.name)

    refute :destroy in action_names
  end

  test "supersede points an amended record forward (D10)" do
    old = create_org(%{name: "Old Corp", ein: "333333333"})
    new = create_org(%{name: "New Corp", ein: "444444444"})

    old =
      old
      |> Ash.Changeset.for_update(:update, %{superseded_by_id: new.id})
      |> Ash.update!()
      |> Ash.load!(:superseded_by)

    assert old.superseded_by.id == new.id
  end
end
