defmodule Mix.Tasks.Nonprofiteer.ResourcesTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Nonprofiteer.Resources

  test "with no argument, lists resources grouped by domain" do
    output = capture_io(fn -> Resources.run([]) end)

    assert output =~ "Registered resources (5)"
    assert output =~ "Nonprofiteer.Orgs:"
    assert output =~ "Nonprofiteer.Orgs.Organization"
    assert output =~ "Nonprofiteer.Orgs.Address"
    assert output =~ "Nonprofiteer.Orgs.Filing"
    assert output =~ "Nonprofiteer.Orgs.Person"
    assert output =~ "Nonprofiteer.Ingest:"
    assert output =~ "Nonprofiteer.Ingest.Run"
  end

  test "prints a resource's shape by short name" do
    output = capture_io(fn -> Resources.run(["Organization"]) end)

    assert output =~ "== Nonprofiteer.Orgs.Organization =="
    assert output =~ "AshPostgres → table \"organizations\""
    assert output =~ "primary key: id"
    assert output =~ "ein: :string"
    assert output =~ "name: :string (required)"
    assert output =~ "belongs_to central_org"
    assert output =~ "has_many subordinates"
    assert output =~ "update tombstone"
  end

  test "prints a resource's shape by fully-qualified module name" do
    output = capture_io(fn -> Resources.run(["Nonprofiteer.Orgs.Address"]) end)

    assert output =~ "== Nonprofiteer.Orgs.Address =="
    assert output =~ "country: :string (default \"US\")"
  end

  test "unknown name with near matches fuzzy-lists them" do
    output = capture_io(fn -> Resources.run(["org"]) end)

    assert output =~ "Matching resources (1)"
    assert output =~ "Nonprofiteer.Orgs.Organization"
  end

  test "unknown name with no matches says so" do
    output = capture_io(fn -> Resources.run(["zzz-nope"]) end)

    assert output =~ "No matching resources"
  end
end
