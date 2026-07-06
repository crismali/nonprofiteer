defmodule Nonprofiteer.Ingest.Efile.PartViiTest do
  use ExUnit.Case, async: true

  alias Nonprofiteer.Ingest.Efile.PartVii
  alias Nonprofiteer.Ingest.Efile.PartVii.UnsupportedReturnError

  defp real_return, do: File.read!("test/fixtures/990/form990_2020.xml")

  # A minimal but structurally-real modern 990 for edge cases.
  defp return(opts) do
    version = Keyword.get(opts, :version, "2020v4.0")
    return_type = Keyword.get(opts, :return_type, "990")
    body = Keyword.get(opts, :body, "")

    """
    <Return xmlns="http://www.irs.gov/efile" returnVersion="#{version}">
      <ReturnHeader>
        <ReturnTypeCd>#{return_type}</ReturnTypeCd>
        <TaxYr>2020</TaxYr>
        <Filer>
          <EIN>123456789</EIN>
          <USAddress>
            <AddressLine1Txt>1 A ST</AddressLine1Txt>
            <CityNm>TOWN</CityNm>
            <StateAbbreviationCd>CA</StateAbbreviationCd>
            <ZIPCd>90001</ZIPCd>
          </USAddress>
        </Filer>
      </ReturnHeader>
      <ReturnData><IRS990>#{body}</IRS990></ReturnData>
    </Return>
    """
  end

  test "parses the filing header from a real return (known-answer)" do
    parsed = PartVii.parse!(real_return())

    assert parsed.ein == "815406671"
    assert parsed.return_type == :form_990
    assert parsed.tax_year == 2020
    assert parsed.schema_version == "2020v4.0"

    assert parsed.address == %{
             line1: "142 E MAIN ST",
             line2: nil,
             city: "FOREST CITY",
             region: "NC",
             postal_code: "28043",
             country: "US"
           }
  end

  test "extracts the Part VII Section A people in listing order (known-answer)" do
    %{people: people} = PartVii.parse!(real_return())

    assert length(people) == 9
    assert Enum.at(people, 0) == %{name: "MICKEY BLAND", title: "MEMBER", part_vii_sequence: 0}
    assert Enum.at(people, 1).name == "DAVID EAKER"
    assert Enum.at(people, 1).title == "TREASURER"

    assert List.last(people) == %{
             name: "BIRGIRT DILGERT",
             title: "DIRECTOR",
             part_vii_sequence: 8
           }
  end

  test "reads a business-entity listee from BusinessName" do
    body = """
    <Form990PartVIISectionAGrp>
      <BusinessName><BusinessNameLine1Txt>ACME MGMT LLC</BusinessNameLine1Txt></BusinessName>
      <TitleTxt>MANAGER</TitleTxt>
    </Form990PartVIISectionAGrp>
    """

    assert %{people: [person]} = PartVii.parse!(return(body: body))
    assert person == %{name: "ACME MGMT LLC", title: "MANAGER", part_vii_sequence: 0}
  end

  test "raises (loud-skip) on a pre-2013 schema version" do
    assert_raise UnsupportedReturnError, ~r/schema version/, fn ->
      PartVii.parse!(return(version: "2011v1.2"))
    end
  end

  test "raises (loud-skip) on a non-990 return type" do
    assert_raise UnsupportedReturnError, ~r/Form 990 only/, fn ->
      PartVii.parse!(return(return_type: "990EZ"))
    end
  end

  test "raises on unparseable XML rather than returning empty" do
    assert_raise UnsupportedReturnError, ~r/unparseable/, fn -> PartVii.parse!("not xml <<<") end
  end
end
