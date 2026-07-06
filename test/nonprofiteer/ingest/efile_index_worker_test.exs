defmodule Nonprofiteer.Ingest.EfileIndexWorkerTest do
  use Nonprofiteer.DataCase, async: false
  use Oban.Testing, repo: Nonprofiteer.Repo

  alias Nonprofiteer.Ingest.EfileIndexWorker
  alias Nonprofiteer.Ingest.EfileParseWorker
  alias Nonprofiteer.Ingest.Run
  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Organization

  # The two Form 990 rows in the fixture (990EZ rows must be filtered out).
  @form_990_2018 "201921359349311872"
  @form_990_2013 "201410859349300511"
  @form_990ez "202301529349200315"

  setup do
    Application.put_env(:nonprofiteer, :efile_index_url, "https://stub/index.csv")
    Application.put_env(:nonprofiteer, :http_req_opts, plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.delete_env(:nonprofiteer, :efile_index_url)
      Application.delete_env(:nonprofiteer, :efile_min_tax_year)
      Application.delete_env(:nonprofiteer, :http_req_opts)
    end)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.text(conn, File.read!("test/fixtures/990/index_sample.csv"))
    end)

    :ok
  end

  defp run(args \\ %{}), do: perform_job(EfileIndexWorker, args)

  test "fans out a parse job per in-scope Form 990, skipping other forms" do
    Application.put_env(:nonprofiteer, :efile_min_tax_year, 2010)

    assert :ok = run()

    assert_enqueued(worker: EfileParseWorker, args: %{"object_id" => @form_990_2018})
    assert_enqueued(worker: EfileParseWorker, args: %{"object_id" => @form_990_2013})
    refute_enqueued(worker: EfileParseWorker, args: %{"object_id" => @form_990ez})

    assert [run] = Ash.read!(Run)
    assert run.source == :efile_990
    assert run.extract_id == "index"
    assert run.row_count == 2
  end

  test "applies the tax-year cutoff" do
    Application.put_env(:nonprofiteer, :efile_min_tax_year, 2015)

    assert :ok = run()

    # Only the TY-2018 return clears a 2015 cutoff; the TY-2013 one is filtered.
    assert_enqueued(worker: EfileParseWorker, args: %{"object_id" => @form_990_2018})
    refute_enqueued(worker: EfileParseWorker, args: %{"object_id" => @form_990_2013})
  end

  test "does not re-enqueue an already-ingested filing" do
    Application.put_env(:nonprofiteer, :efile_min_tax_year, 2010)

    org =
      Organization
      |> Ash.Changeset.for_create(:upsert_from_bmf, %{ein: "260887716", name: "Org"})
      |> Ash.create!()

    Filing
    |> Ash.Changeset.for_create(:upsert_from_efile, %{
      organization_id: org.id,
      return_type: :form_990,
      tax_year: 2018,
      source_object_id: @form_990_2018
    })
    |> Ash.create!()

    assert :ok = run()

    refute_enqueued(worker: EfileParseWorker, args: %{"object_id" => @form_990_2018})
    assert_enqueued(worker: EfileParseWorker, args: %{"object_id" => @form_990_2013})
  end
end
