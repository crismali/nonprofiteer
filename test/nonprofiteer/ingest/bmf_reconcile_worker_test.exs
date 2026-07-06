defmodule Nonprofiteer.Ingest.BmfReconcileWorkerTest do
  use Nonprofiteer.DataCase, async: false
  use Oban.Testing, repo: Nonprofiteer.Repo

  import ExUnit.CaptureLog

  alias Nonprofiteer.Ingest.BmfReconcileWorker
  alias Nonprofiteer.Ingest.Run
  alias Nonprofiteer.Orgs.Organization

  defp upsert_org(attrs) do
    Organization
    |> Ash.Changeset.for_create(:upsert_from_bmf, attrs)
    |> Ash.create!()
  end

  defp reload(org), do: Ash.get!(Organization, org.id)

  test "links subordinates to their central by shared GEN and counts the unresolved" do
    # A GEN-0925 group: one central (AFFILIATION 6) with subordinates that, in reality, live in
    # other state files — the whole point of a global reconcile.
    central =
      upsert_org(%{
        ein: "350868122",
        name: "AMERICAN LEGION NATIONAL",
        gen: "0925",
        affiliation_code: "6"
      })

    sub1 =
      upsert_org(%{
        ein: "010631747",
        name: "AMERICAN LEGION POST 1",
        gen: "0925",
        affiliation_code: "9"
      })

    sub2 =
      upsert_org(%{
        ein: "201681093",
        name: "AMERICAN LEGION POST 2",
        gen: "0925",
        affiliation_code: "9"
      })

    # A second group whose central is AFFILIATION 8 (a denominational central) — must link too.
    lutheran_central =
      upsert_org(%{
        ein: "416053173",
        name: "OLD APOSTOLIC LUTHERAN",
        gen: "1598",
        affiliation_code: "8"
      })

    lutheran_sub =
      upsert_org(%{
        ein: "999999998",
        name: "LUTHERAN CONGREGATION",
        gen: "1598",
        affiliation_code: "9"
      })

    # An independent org (no group) and a subordinate whose central isn't in the dataset.
    independent = upsert_org(%{ein: "111111111", name: "INDIE ORG", affiliation_code: "3"})

    orphan_sub =
      upsert_org(%{ein: "222222222", name: "ORPHAN SUB", gen: "9999", affiliation_code: "9"})

    assert :ok = perform_job(BmfReconcileWorker, %{})

    assert reload(sub1).central_org_id == central.id
    assert reload(sub2).central_org_id == central.id
    assert reload(lutheran_sub).central_org_id == lutheran_central.id

    # Centrals, independents, and centrally-orphaned subordinates are left unlinked.
    assert reload(central).central_org_id == nil
    assert reload(independent).central_org_id == nil
    assert reload(orphan_sub).central_org_id == nil

    assert [run] = Ash.read!(Run)
    assert run.extract_id == "reconcile"
    assert run.status == :success
    assert run.row_count == 3
    assert run.orphan_skipped_count == 1
  end

  test "picks the lowest-EIN central deterministically and flags a GEN with multiple centrals" do
    # Two centrals share GEN 0925 — a BMF anomaly. The lower EIN should win, whatever read
    # order Postgres returns.
    _high_ein =
      upsert_org(%{ein: "900000001", name: "CENTRAL HIGH", gen: "0925", affiliation_code: "6"})

    low_ein =
      upsert_org(%{ein: "100000002", name: "CENTRAL LOW", gen: "0925", affiliation_code: "8"})

    sub = upsert_org(%{ein: "010631747", name: "SUB", gen: "0925", affiliation_code: "9"})

    log =
      capture_log(fn ->
        assert :ok = perform_job(BmfReconcileWorker, %{})
      end)

    assert reload(sub).central_org_id == low_ein.id
    assert log =~ "1 GEN(s) list multiple centrals"
    assert log =~ "0925"
  end

  test "is idempotent — re-running keeps the links and reports the same counts" do
    central = upsert_org(%{ein: "350868122", name: "CENTRAL", gen: "0925", affiliation_code: "6"})
    sub = upsert_org(%{ein: "010631747", name: "SUB", gen: "0925", affiliation_code: "9"})

    assert :ok = perform_job(BmfReconcileWorker, %{})
    assert :ok = perform_job(BmfReconcileWorker, %{})

    assert reload(sub).central_org_id == central.id

    runs = Ash.read!(Run)
    assert length(runs) == 2
    assert Enum.all?(runs, &(&1.status == :success and &1.row_count == 1))
  end
end
