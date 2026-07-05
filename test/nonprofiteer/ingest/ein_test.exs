defmodule Nonprofiteer.Ingest.EinTest do
  use ExUnit.Case, async: true

  alias Nonprofiteer.Ingest.Ein

  doctest Ein

  test "keeps a clean 9-digit EIN, leading zeros intact" do
    assert Ein.normalize("010631747") == "010631747"
    assert Ein.normalize("530196605") == "530196605"
  end

  test "strips separators and surrounding whitespace" do
    assert Ein.normalize("01-0631747") == "010631747"
    assert Ein.normalize(" 53-0196605 ") == "530196605"
  end

  test "recovers a dropped leading zero from an 8-digit value" do
    assert Ein.normalize("10631747") == "010631747"
  end

  test "rejects anything that can't be a 9-digit EIN" do
    assert Ein.normalize(nil) == nil
    assert Ein.normalize("") == nil
    assert Ein.normalize("123") == nil
    assert Ein.normalize("1234567890") == nil
    assert Ein.normalize("N/A") == nil
  end
end
