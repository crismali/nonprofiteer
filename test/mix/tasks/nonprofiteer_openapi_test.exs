defmodule Mix.Tasks.Nonprofiteer.OpenapiTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Nonprofiteer.Openapi

  defp tmp_path do
    Path.join(
      System.tmp_dir!(),
      "nonprofiteer_openapi_#{System.unique_integer([:positive])}.json"
    )
  end

  test "writes a prefixed OpenAPI document to the given path" do
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)

    output = capture_io(fn -> assert :ok = Openapi.run([path]) end)
    assert output =~ "Wrote OpenAPI spec to #{path}"

    spec = path |> File.read!() |> Jason.decode!()
    assert spec["openapi"] =~ "3."
    assert Map.has_key?(spec["paths"], "/api/v1/sync/addresses")
  end

  test "defaults to openapi.json when no path is given" do
    on_exit(fn -> File.rm("openapi.json") end)

    capture_io(fn -> assert :ok = Openapi.run([]) end)
    assert File.exists?("openapi.json")
  end
end
