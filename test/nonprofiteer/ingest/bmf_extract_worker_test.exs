defmodule Nonprofiteer.Ingest.BmfExtractWorkerTest do
  use Nonprofiteer.DataCase, async: false
  use Oban.Testing, repo: Nonprofiteer.Repo

  require Ash.Query

  alias Nonprofiteer.Ingest.Bmf
  alias Nonprofiteer.Ingest.BmfExtractWorker
  alias Nonprofiteer.Ingest.Run
  alias Nonprofiteer.Orgs.Address
  alias Nonprofiteer.Orgs.Organization

  @url "https://www.irs.gov/pub/irs-soi/eo1.csv"

  setup do
    Application.put_env(:nonprofiteer, :http_req_opts, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:nonprofiteer, :http_req_opts) end)
    :ok
  end

  defp stub_body(csv) do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.text(conn, csv) end)
  end

  defp run_extract(extract_id \\ "eo1") do
    perform_job(BmfExtractWorker, %{"url" => @url, "extract_id" => extract_id})
  end

  defp org_by_ein(ein) do
    Organization
    |> Ash.Query.filter(ein == ^ein)
    |> Ash.read_one!()
  end

  test "downloads, parses, and upserts the extract into orgs + addresses (known-answer)" do
    stub_body(File.read!("test/fixtures/bmf/eo_sample.csv"))

    assert :ok = run_extract()

    assert length(Ash.read!(Organization)) == 3

    org = org_by_ein("010000028") |> Ash.load!(:address)
    assert org.name == "ALEXANDRIA MUSEUM, INC"
    assert org.source == :bmf
    assert org.ntee_code == "A20"
    assert org.address.region == "VA"
    assert org.address.postal_code == "22301"

    red_cross = org_by_ein("530196605")
    assert red_cross.gen == "0928"
    assert red_cross.affiliation_code == "9"
  end

  test "records a success run row with counts" do
    stub_body(File.read!("test/fixtures/bmf/eo_sample.csv"))

    run_extract("eo1")

    assert [run] = Ash.read!(Run)
    assert run.source == :bmf
    assert run.extract_id == "eo1"
    assert run.status == :success
    assert run.row_count == 3
    assert run.orphan_skipped_count == 0
  end

  test "is idempotent — re-running converges instead of duplicating, updating address in place" do
    stub_body(File.read!("test/fixtures/bmf/eo_sample.csv"))
    run_extract()

    org = org_by_ein("010000028")
    original_address_id = org.address_id

    # The org moved: same EIN, new street in the next monthly drop.
    moved =
      "test/fixtures/bmf/eo_sample.csv"
      |> File.read!()
      |> String.replace("123 MAIN ST", "456 NEW ST")

    stub_body(moved)
    run_extract()

    # No duplicate org or address rows.
    assert length(Ash.read!(Organization)) == 3
    assert length(Ash.read!(Address)) == 3

    # Same address row, updated in place.
    reloaded = org_by_ein("010000028") |> Ash.load!(:address)
    assert reloaded.address_id == original_address_id
    assert reloaded.address.line1 == "456 NEW ST"
  end

  test "skips EIN-less rows as orphans without corrupting the spine" do
    header =
      "test/fixtures/bmf/eo_sample.csv" |> File.read!() |> String.split("\n") |> hd()

    valid =
      "010000028,\"ALEXANDRIA MUSEUM, INC\",,123 MAIN ST,ALEXANDRIA,VA,22301,0000,03,3," <>
        "1000,199001,1,15,0,1,01,201812,4,4,01,0,12,250000,300000,290000,A20,ALEXANDRIA MUSEUM"

    orphan =
      ",\"NO EIN ORG\",,1 NOWHERE,NOWHERE,NA,00000,0000,03,3," <>
        "1000,199001,1,15,0,1,01,201812,4,4,01,0,12,0,0,0,A20,NO EIN ORG"

    stub_body(Enum.join([header, valid, orphan], "\n") <> "\n")

    run_extract()

    assert length(Ash.read!(Organization)) == 1
    assert [run] = Ash.read!(Run)
    assert run.row_count == 1
    assert run.orphan_skipped_count == 1
  end

  test "header drift fails loud and records a failure run row" do
    drifted =
      "test/fixtures/bmf/eo_sample.csv"
      |> File.read!()
      |> String.replace_prefix("EIN,NAME", "NAME,EIN")

    stub_body(drifted)

    assert_raise Bmf.LayoutError, fn -> run_extract("eo1") end

    assert [] = Ash.read!(Organization)
    assert [run] = Ash.read!(Run)
    assert run.status == :failure
    assert run.extract_id == "eo1"
    assert run.error_message =~ "header drift"
  end
end
