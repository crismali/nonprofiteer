defmodule Nonprofiteer.Ingest.Efile.IrsxCrosscheckTest do
  use ExUnit.Case, async: true

  alias Nonprofiteer.Ingest.Efile.IrsxCrosscheck

  # A minimal modern 990 carrying two Part VII Section A groups — one individual, one business.
  defp return(groups) do
    """
    <Return xmlns="http://www.irs.gov/efile" returnVersion="2020v4.0">
      <ReturnHeader>
        <ReturnTypeCd>990</ReturnTypeCd>
        <TaxYr>2020</TaxYr>
        <Filer><EIN>123456789</EIN></Filer>
      </ReturnHeader>
      <ReturnData><IRS990>#{groups}</IRS990></ReturnData>
    </Return>
    """
  end

  @two_people """
  <Form990PartVIISectionAGrp>
    <PersonNm>Ada Lovelace</PersonNm>
    <TitleTxt>President</TitleTxt>
  </Form990PartVIISectionAGrp>
  <Form990PartVIISectionAGrp>
    <BusinessName><BusinessNameLine1Txt>ACME MGMT LLC</BusinessNameLine1Txt></BusinessName>
    <TitleTxt>Manager</TitleTxt>
  </Form990PartVIISectionAGrp>
  """

  # IRSx `--schedule IRS990 --format json` shape: a one-element list whose `groups` holds the
  # concordance-named Part VII group. Mirrors the two listees above.
  defp irsx_json(rows) do
    Jason.encode!([%{"groups" => %{"Frm990PrtVIISctnA" => rows}}])
  end

  describe "ours_from_xml/1" do
    test "reduces our Part VII people to {name, title}, individuals and businesses alike" do
      assert IrsxCrosscheck.ours_from_xml(return(@two_people)) ==
               [{"Ada Lovelace", "President"}, {"ACME MGMT LLC", "Manager"}]
    end
  end

  describe "theirs_from_json/1" do
    test "pulls IRSx listees from the concordance group, falling back to the business name" do
      json =
        irsx_json([
          %{"PrsnNm" => "Ada Lovelace", "TtlTxt" => "President"},
          %{"BsnssNmLn1Txt" => "ACME MGMT LLC", "TtlTxt" => "Manager"}
        ])

      assert IrsxCrosscheck.theirs_from_json(json) ==
               [{"Ada Lovelace", "President"}, {"ACME MGMT LLC", "Manager"}]
    end

    test "a missing Part VII group (schema drift) yields an empty list, not a crash" do
      assert IrsxCrosscheck.theirs_from_json(Jason.encode!([%{"groups" => %{}}])) == []
      assert IrsxCrosscheck.theirs_from_json(Jason.encode!([])) == []
    end
  end

  describe "compare/2" do
    test "matches identical ordered listee lists" do
      listees = [{"Ada Lovelace", "President"}, {"ACME MGMT LLC", "Manager"}]
      report = IrsxCrosscheck.compare(listees, listees)

      assert report.match?
      assert report.mismatches == []
    end

    test "reports a per-index disagreement" do
      report =
        IrsxCrosscheck.compare(
          [{"Ada Lovelace", "President"}],
          [{"Ada Lovelace", "Chair"}]
        )

      refute report.match?
      assert report.mismatches == [{0, {"Ada Lovelace", "President"}, {"Ada Lovelace", "Chair"}}]
    end

    test "a dropped row on one side shows the trailing index with a nil counterpart" do
      report = IrsxCrosscheck.compare([{"A", nil}, {"B", nil}], [{"A", nil}])

      refute report.match?
      assert report.mismatches == [{1, {"B", nil}, nil}]
    end
  end

  describe "format_report/2" do
    test "summarizes a match on one line" do
      report = IrsxCrosscheck.compare([{"A", "T"}], [{"A", "T"}])

      assert IrsxCrosscheck.format_report("acme", report) =~
               "✓ acme: 1 Part VII Section A listees match"
    end

    test "lists each mismatch under a failing header" do
      report = IrsxCrosscheck.compare([{"A", "T"}], [{"A", "X"}])
      out = IrsxCrosscheck.format_report("acme", report)

      assert out =~ "✗ acme: ours=1 irsx=1"
      assert out =~ ~s([0] ours={"A", "T"} irsx={"A", "X"})
    end
  end

  test "end-to-end: our XML parse matches an equivalent IRSx JSON payload" do
    ours = IrsxCrosscheck.ours_from_xml(return(@two_people))

    theirs =
      IrsxCrosscheck.theirs_from_json(
        irsx_json([
          %{"PrsnNm" => "Ada Lovelace", "TtlTxt" => "President"},
          %{"BsnssNmLn1Txt" => "ACME MGMT LLC", "TtlTxt" => "Manager"}
        ])
      )

    assert IrsxCrosscheck.compare(ours, theirs).match?
  end
end
