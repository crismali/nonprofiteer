defmodule Nonprofiteer.Ingest.ClientTest do
  use ExUnit.Case, async: true

  alias Nonprofiteer.Ingest.Client

  setup do
    Application.put_env(:nonprofiteer, :http_req_opts, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:nonprofiteer, :http_req_opts) end)
    :ok
  end

  test "fetch!/1 returns the whole body" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.text(conn, "hello body") end)

    assert Client.fetch!("https://x/file") == "hello body"
  end

  test "stream!/1 returns an enumerable of body chunks" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.text(conn, "a\nb\nc\n") end)

    chunks = "https://x/file" |> Client.stream!() |> Enum.to_list()

    assert IO.iodata_to_binary(chunks) == "a\nb\nc\n"
  end
end
