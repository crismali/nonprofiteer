defmodule Nonprofiteer.Orgs.Preparations.ChangedSinceTest do
  # One test flips the watermark lag (global app env), so keep this file out of the async pool.
  use Nonprofiteer.DataCase, async: false

  alias Nonprofiteer.Orgs.Organization

  defp create_org(attrs) do
    Organization |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  defp changed_since do
    Organization |> Ash.Query.for_read(:changed_since) |> Ash.read!(page: false)
  end

  test "orders results by (updated_at, id)" do
    for n <- 1..5, do: create_org(%{name: "Org #{n}"})

    results = changed_since()

    assert length(results) == 5
    assert results == Enum.sort_by(results, &{&1.updated_at, &1.id})
  end

  test "loads the event_type calculation on each record" do
    create_org(%{name: "Live"})

    assert [record] = changed_since()
    assert record.event_type == :upsert
  end

  test "bounds results by the sync watermark" do
    original = Application.get_env(:nonprofiteer, :sync_watermark_lag_seconds)
    on_exit(fn -> Application.put_env(:nonprofiteer, :sync_watermark_lag_seconds, original) end)

    create_org(%{name: "Too Fresh"})

    # With a large lag the watermark sits well before now, so a just-written row is excluded.
    Application.put_env(:nonprofiteer, :sync_watermark_lag_seconds, 3600)
    assert changed_since() == []

    # Back to the test default (no lag) and the row surfaces.
    Application.put_env(:nonprofiteer, :sync_watermark_lag_seconds, 0)
    assert [%{name: "Too Fresh"}] = changed_since()
  end
end
