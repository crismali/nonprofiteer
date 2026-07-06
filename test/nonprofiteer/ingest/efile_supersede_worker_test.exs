defmodule Nonprofiteer.Ingest.EfileSupersedeWorkerTest do
  use Nonprofiteer.DataCase, async: false
  use Oban.Testing, repo: Nonprofiteer.Repo

  alias Nonprofiteer.Ingest.EfileSupersedeWorker
  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Organization

  defp org do
    Organization |> Ash.Changeset.for_create(:create, %{name: "Org"}) |> Ash.create!()
  end

  defp filing(org, tax_year, filed_on, opts \\ []) do
    attrs =
      Enum.into(opts, %{
        organization_id: org.id,
        return_type: :form_990,
        tax_year: tax_year,
        filed_on: filed_on,
        source_object_id: "obj-#{System.unique_integer([:positive])}"
      })

    Filing |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  defp reload(filing), do: Filing |> Ash.get!(filing.id) |> Ash.load!(:event_type)

  test "supersedes earlier filings by the latest filed in a (org, year, type) group" do
    o = org()
    f1 = filing(o, 2023, ~D[2024-01-15])
    f2 = filing(o, 2023, ~D[2024-05-01])
    latest = filing(o, 2023, ~D[2024-11-20])

    assert :ok = perform_job(EfileSupersedeWorker, %{})

    assert reload(f1).superseded_by_id == latest.id
    assert reload(f2).superseded_by_id == latest.id
    assert reload(latest).superseded_by_id == nil

    # Composes with the feed (D16): the superseded filing's derived event_type flips.
    assert reload(f1).event_type == :superseded
    assert reload(latest).event_type == :upsert
  end

  test "leaves a lone filing in its group untouched" do
    o = org()
    f = filing(o, 2023, ~D[2024-01-15])

    perform_job(EfileSupersedeWorker, %{})

    assert reload(f).superseded_by_id == nil
  end

  test "keeps groups independent across tax year and return type" do
    o = org()
    older = filing(o, 2022, ~D[2023-05-01])
    newer = filing(o, 2022, ~D[2023-09-01])
    ez = filing(o, 2022, ~D[2023-10-01], return_type: :form_990_ez)

    perform_job(EfileSupersedeWorker, %{})

    assert reload(older).superseded_by_id == newer.id
    # The 990-EZ is alone in its (org, 2022, 990EZ) group.
    assert reload(ez).superseded_by_id == nil
  end

  test "is idempotent" do
    o = org()
    f1 = filing(o, 2023, ~D[2024-01-15])
    latest = filing(o, 2023, ~D[2024-11-20])

    perform_job(EfileSupersedeWorker, %{})
    perform_job(EfileSupersedeWorker, %{})

    assert reload(f1).superseded_by_id == latest.id
    assert reload(latest).superseded_by_id == nil
  end
end
