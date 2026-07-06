defmodule Nonprofiteer.KnownAnswersTest do
  @moduledoc """
  End-to-end known-answer validation against **real** captured IRS data (see docs/EXAMPLES.md).

  Runs the actual pipeline — BMF org spine → 990 Part VII parse — over committed fixtures for a
  documented dark-money↔FEC bridge, asserting the exact officers/addresses the bridge hinges on.
  This is the drift guard the architecture calls for: Part VII parse bugs fail *silently*, so
  without these known-answer assertions "working" and "quietly dropping half the officers" look
  identical. Re-capture the fixtures with `mix nonprofiteer.capture_known_answers` and diff.
  """
  use Nonprofiteer.DataCase, async: false
  use Oban.Testing, repo: Nonprofiteer.Repo

  require Ash.Query

  alias Nonprofiteer.Ingest.Bmf
  alias Nonprofiteer.Ingest.EfileParseWorker
  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Organization
  alias Nonprofiteer.Orgs.Person

  @fixtures "test/fixtures/known_answers"
  @aan_ein "270730508"
  @forum_ein "270567765"

  setup do
    # Seed the org spine from the real captured BMF rows, so the 990 parse links (not orphans).
    "#{@fixtures}/bmf_dc_known.csv"
    |> File.read!()
    |> Bmf.parse!()
    |> Enum.each(fn %{org: org_attrs} ->
      Organization |> Ash.Changeset.for_create(:upsert_from_bmf, org_attrs) |> Ash.create!()
    end)

    Application.put_env(:nonprofiteer, :http_req_opts, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:nonprofiteer, :http_req_opts) end)
    :ok
  end

  defp parse_return(object_id, xml_file, filed_on) do
    xml = File.read!("#{@fixtures}/#{xml_file}")
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.text(conn, xml) end)

    assert :ok =
             perform_job(EfileParseWorker, %{
               "object_id" => object_id,
               "xml_url" => "https://stub/#{object_id}.xml",
               "filed_on" => filed_on
             })
  end

  defp org_by_ein(ein), do: Organization |> Ash.Query.filter(ein == ^ein) |> Ash.read_one!()

  defp people_for(org), do: Person |> Ash.Query.filter(organization_id == ^org.id) |> Ash.read!()

  test "American Action Network (c4) — the shared-officer bridge to Congressional Leadership Fund" do
    parse_return("202201369349304100", "american_action_network_990.xml", "2022-05-16")

    org = org_by_ein(@aan_ein)
    assert org.source == :bmf
    assert org.name == "AMERICAN ACTION NETWORK INC"

    assert [filing] = Ash.read!(Filing) |> Enum.filter(&(&1.organization_id == org.id))
    assert filing.return_type == :form_990
    assert filing.tax_year == 2020

    people = people_for(org)
    assert length(people) == 15

    # Daniel Conston, AAN president, is also president of the Congressional Leadership Fund Super
    # PAC (C00504530) — the documented officer overlap ohfec's name+address matcher bridges on.
    conston = Enum.find(people, &(&1.name == "Daniel Conston"))
    assert conston.title == "President"
    assert conston.part_vii_sequence == 0

    # D8 corroboration address — the filer's business address, stored raw (ohfec normalizes).
    conston = Ash.load!(conston, :address)
    assert conston.address.line1 == "1747 Pennsylvania Avenue NW 5th fl"
    assert conston.address.region == "DC"
  end

  test "American Action Forum (c3) — the shared-address bridge (raw forms differ)" do
    parse_return("202311359349309026", "american_action_forum_990.xml", "2023-05-15")

    org = org_by_ein(@forum_ein)
    assert org.name == "AMERICAN ACTION FORUM INC"

    people = people_for(org)
    assert length(people) == 15

    # Same 1747 Pennsylvania Ave office as AAN, but a different raw string — the overlap only
    # fires after the consumer normalizes, which is exactly why we store raw (D2/D4/D15).
    [person | _] = people
    person = Ash.load!(person, :address)
    assert person.address.line1 == "1747 PENNSYLVANIA AVE NW 5TH FLOO"
    assert person.address.region == "DC"
  end
end
