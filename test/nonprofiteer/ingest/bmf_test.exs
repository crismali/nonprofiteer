defmodule Nonprofiteer.Ingest.BmfTest do
  use ExUnit.Case, async: true

  alias Nonprofiteer.Ingest.Bmf

  defp sample, do: File.read!("test/fixtures/bmf/eo_sample.csv")

  test "parses each data row into org + address attribute maps (known-answer)" do
    assert [alexandria, red_cross, big_sur] = Bmf.parse!(sample())

    assert alexandria.org == %{
             ein: "010000028",
             name: "ALEXANDRIA MUSEUM, INC",
             ntee_code: "A20",
             gen: nil,
             affiliation_code: "3"
           }

    assert alexandria.address == %{
             line1: "123 MAIN ST",
             city: "ALEXANDRIA",
             region: "VA",
             postal_code: "22301",
             country: "US"
           }

    # A real GROUP exemption number is kept; the address region tracks the STATE column. The
    # AFFILIATION code (9 = group subordinate) is captured raw for the later GEN reconcile.
    assert red_cross.org.gen == "0928"
    assert red_cross.org.ntee_code == "E60"
    assert red_cross.org.affiliation_code == "9"
    assert red_cross.address.region == "DC"

    # Blank NTEE normalizes to nil; GROUP "0000" means "no group" → nil.
    assert big_sur.org.ntee_code == nil
    assert big_sur.org.gen == nil
  end

  test "preserves a quoted name containing a comma" do
    assert [%{org: %{name: "ALEXANDRIA MUSEUM, INC"}} | _] = Bmf.parse!(sample())
  end

  test "raises LayoutError on header drift so a bad parse fails loud, not silent" do
    drifted =
      sample()
      |> String.replace_prefix("EIN,NAME", "NAME,EIN")

    assert_raise Bmf.LayoutError, ~r/header drift/, fn -> Bmf.parse!(drifted) end
  end

  # The layout pin only catches drift when *some* extract runs it. `eo_sample.csv` above is
  # hand-crafted (its rows back the known-answer assertions), so it can't double as a live
  # canary. `bmf_dc_known.csv` is captured from a real irs.gov extract by
  # `mix nonprofiteer.capture_known_answers` — re-run that periodically and this test turns a
  # silently-drifted IRS layout into a loud, deliberate failure the moment the fixture updates,
  # instead of waiting for a production BmfExtractWorker to raise.
  test "the live-captured IRS header still matches the pinned layout (drift canary)" do
    real = File.read!("test/fixtures/known_answers/bmf_dc_known.csv")

    assert [_ | _] = Bmf.parse!(real)
  end
end
