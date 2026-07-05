defmodule Nonprofiteer.Orgs.AddressTest do
  use Nonprofiteer.DataCase, async: true

  alias Nonprofiteer.Orgs.Address

  defp create_address(attrs) do
    Address
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  test "creates an address and defaults country to US" do
    address = create_address(%{line1: "1 Main St", city: "Springfield", region: "IL"})

    assert address.line1 == "1 Main St"
    assert address.city == "Springfield"
    assert address.region == "IL"
    assert address.country == "US"
  end

  test "country can be overridden" do
    address = create_address(%{line1: "10 Downing St", city: "London", country: "GB"})

    assert address.country == "GB"
  end

  test "updates an address" do
    address = create_address(%{line1: "1 Main St", city: "Springfield"})

    updated =
      address
      |> Ash.Changeset.for_update(:update, %{postal_code: "62704"})
      |> Ash.update!()

    assert updated.postal_code == "62704"
  end

  test "destroys an address" do
    address = create_address(%{line1: "1 Main St"})

    assert :ok = Ash.destroy!(address)
    assert Ash.read!(Address) == []
  end
end
