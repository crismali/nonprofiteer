defmodule Nonprofiteer.Ingest.BmfCoordinatorWorkerTest do
  use Nonprofiteer.DataCase, async: false
  use Oban.Testing, repo: Nonprofiteer.Repo

  alias Nonprofiteer.Ingest.BmfCoordinatorWorker
  alias Nonprofiteer.Ingest.BmfExtractWorker

  test "fans out one extract job per configured extract" do
    Application.put_env(:nonprofiteer, :bmf_extracts, [
      %{id: "eo_test", url: "https://example.test/eo_test.csv"}
    ])

    on_exit(fn -> Application.delete_env(:nonprofiteer, :bmf_extracts) end)

    assert :ok = perform_job(BmfCoordinatorWorker, %{})

    assert_enqueued(
      worker: BmfExtractWorker,
      args: %{"extract_id" => "eo_test", "url" => "https://example.test/eo_test.csv"}
    )
  end

  test "defaults to the IRS regional EO BMF extract set" do
    assert length(BmfCoordinatorWorker.extracts()) == 4
  end
end
