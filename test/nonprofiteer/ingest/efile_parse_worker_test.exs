defmodule Nonprofiteer.Ingest.EfileParseWorkerTest do
  use Nonprofiteer.DataCase, async: false
  use Oban.Testing, repo: Nonprofiteer.Repo

  alias Nonprofiteer.Ingest.EfileParseWorker
  alias Nonprofiteer.Orgs.Address
  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Organization
  alias Nonprofiteer.Orgs.Person

  @object_id "202211339349308111"
  @url "https://gt990datalake-rawdata.s3.amazonaws.com/EfileData/XmlFiles/#{@object_id}_public.xml"
  # EIN of the RUTHERFORD COUNTY... return in the fixture.
  @filer_ein "815406671"

  setup do
    Application.put_env(:nonprofiteer, :http_req_opts, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:nonprofiteer, :http_req_opts) end)
    :ok
  end

  defp stub(xml), do: Req.Test.stub(__MODULE__, fn conn -> Req.Test.text(conn, xml) end)

  defp seed_org(ein) do
    Organization
    |> Ash.Changeset.for_create(:upsert_from_bmf, %{ein: ein, name: "Seeded Org"})
    |> Ash.create!()
  end

  defp run(args \\ %{}) do
    defaults = %{"object_id" => @object_id, "xml_url" => @url, "filed_on" => "2022-05-13"}
    perform_job(EfileParseWorker, Map.merge(defaults, args))
  end

  defp fixture, do: File.read!("test/fixtures/990/form990_2020.xml")

  test "parses a return into a filing + Part VII people linked to the spine (known-answer)" do
    org = seed_org(@filer_ein)
    stub(fixture())

    assert :ok = run()

    assert [filing] = Ash.read!(Filing)
    assert filing.organization_id == org.id
    assert filing.return_type == :form_990
    assert filing.tax_year == 2020
    assert filing.source_object_id == @object_id
    assert filing.filed_on == ~D[2022-05-13]
    assert filing.schema_version == "2020v4.0"

    people = Ash.read!(Person)
    assert length(people) == 9

    lead = Enum.find(people, &(&1.part_vii_sequence == 0))
    assert lead.name == "MICKEY BLAND"
    assert lead.title == "MEMBER"
    assert lead.filing_id == filing.id
    assert lead.organization_id == org.id

    # All nine share the one filer business address.
    assert [address] = Ash.read!(Address)
    assert address.line1 == "142 E MAIN ST"
    assert address.region == "NC"
    assert Enum.all?(people, &(&1.address_id == address.id))
  end

  test "is idempotent — re-parsing converges (no duplicate filing/people/address)" do
    seed_org(@filer_ein)
    stub(fixture())

    assert :ok = run()
    assert :ok = run()

    assert length(Ash.read!(Filing)) == 1
    assert length(Ash.read!(Person)) == 9
    assert length(Ash.read!(Address)) == 1
  end

  test "skips (no filing) when the EIN isn't in the org spine — orphan" do
    stub(fixture())

    assert :ok = run()

    assert Ash.read!(Filing) == []
    assert Ash.read!(Person) == []
  end

  test "skips (no filing) an out-of-scope return — unsupported schema" do
    seed_org(@filer_ein)

    stub("""
    <Return xmlns="http://www.irs.gov/efile" returnVersion="2011v1.2">
      <ReturnHeader><ReturnTypeCd>990</ReturnTypeCd>
        <Filer><EIN>#{@filer_ein}</EIN></Filer>
      </ReturnHeader>
      <ReturnData><IRS990/></ReturnData>
    </Return>
    """)

    assert :ok = run()
    assert Ash.read!(Filing) == []
  end
end
