defmodule Nonprofiteer.Ingest.ObjectStoreTest do
  use ExUnit.Case, async: false

  alias Nonprofiteer.Ingest.ObjectStore

  doctest ObjectStore

  @config [
    access_key_id: "AK",
    secret_access_key: "SK",
    bucket: "mirror",
    endpoint: "https://acct.r2.cloudflarestorage.com"
  ]

  test "put/2 is a dormant no-op when R2 is unconfigured" do
    assert {:error, :not_configured} = ObjectStore.put("filings/1.xml", "<xml/>")
    refute ObjectStore.configured?()
  end

  describe "when configured" do
    setup do
      Application.put_env(:nonprofiteer, :r2, @config)
      Application.put_env(:nonprofiteer, :r2_req_opts, plug: {Req.Test, __MODULE__})

      on_exit(fn ->
        Application.delete_env(:nonprofiteer, :r2)
        Application.delete_env(:nonprofiteer, :r2_req_opts)
      end)
    end

    test "configured? reflects the resolved config" do
      assert ObjectStore.configured?()
    end

    test "put/2 signs and PUTs the object, returning :ok on 2xx" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/mirror/filings/abc.xml"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert :ok = ObjectStore.put("filings/abc.xml", "<Return/>")
    end

    test "put/2 surfaces a non-2xx as an error" do
      Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, {:http_status, 500, _}} = ObjectStore.put("filings/abc.xml", "<Return/>")
    end
  end
end
