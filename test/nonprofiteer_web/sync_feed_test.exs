defmodule NonprofiteerWeb.SyncFeedTest do
  use NonprofiteerWeb.ConnCase, async: false

  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Organization
  alias Nonprofiteer.Orgs.Person

  defp create_org(attrs) do
    Organization |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  defp next_path(next_url) do
    uri = URI.parse(next_url)
    uri.path <> "?" <> (uri.query || "")
  end

  defp get_feed(conn, path) do
    conn
    |> put_req_header("accept", "application/vnd.api+json")
    |> get(path)
    |> json_response(200)
  end

  test "GET /api/v1/sync/organizations returns changed orgs with a derived event_type", %{
    conn: conn
  } do
    org = create_org(%{name: "ACME Foundation", ein: "123456789"})

    body = get_feed(conn, "/api/v1/sync/organizations")

    assert [record] = body["data"]
    assert record["type"] == "organization"
    assert record["id"] == org.id
    assert record["attributes"]["name"] == "ACME Foundation"
    assert record["attributes"]["event_type"] == "upsert"
  end

  test "event_type reflects tombstone and supersede state", %{conn: conn} do
    live = create_org(%{name: "Live Org"})
    superseding = create_org(%{name: "Superseding Org"})

    create_org(%{name: "Gone Org"})
    |> Ash.Changeset.for_update(:tombstone, %{})
    |> Ash.update!()

    live
    |> Ash.Changeset.for_update(:update, %{superseded_by_id: superseding.id})
    |> Ash.update!()

    body = get_feed(conn, "/api/v1/sync/organizations")
    by_name = Map.new(body["data"], &{&1["attributes"]["name"], &1["attributes"]["event_type"]})

    assert by_name["Gone Org"] == "tombstoned"
    assert by_name["Live Org"] == "superseded"
    assert by_name["Superseding Org"] == "upsert"
  end

  test "watermark hides rows newer than now - lag", %{conn: conn} do
    Application.put_env(:nonprofiteer, :sync_watermark_lag_seconds, 3600)
    on_exit(fn -> Application.put_env(:nonprofiteer, :sync_watermark_lag_seconds, 0) end)

    create_org(%{name: "Too Fresh"})

    body = get_feed(conn, "/api/v1/sync/organizations")
    assert body["data"] == []
  end

  test "the people feed serves Part VII people", %{conn: conn} do
    org = create_org(%{name: "Org", ein: "111111111"})

    filing =
      Filing
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        return_type: :form_990,
        tax_year: 2023
      })
      |> Ash.create!()

    Person
    |> Ash.Changeset.for_create(:create, %{
      organization_id: org.id,
      filing_id: filing.id,
      name: "Jane Director",
      title: "PRESIDENT"
    })
    |> Ash.create!()

    body = get_feed(conn, "/api/v1/sync/people")

    assert [record] = body["data"]
    assert record["type"] == "person"
    assert record["attributes"]["name"] == "Jane Director"
    assert record["attributes"]["event_type"] == "upsert"
  end

  test "keyset pagination resumes via links.next without overlap or gaps", %{conn: conn} do
    for n <- 1..3, do: create_org(%{name: "Org #{n}"})

    page1 = get_feed(conn, "/api/v1/sync/organizations?page[limit]=2")
    assert length(page1["data"]) == 2
    assert next = page1["links"]["next"]

    page2 = get_feed(conn, next_path(next))
    assert length(page2["data"]) == 1

    ids = Enum.map(page1["data"] ++ page2["data"], & &1["id"])
    assert length(Enum.uniq(ids)) == 3
  end
end
