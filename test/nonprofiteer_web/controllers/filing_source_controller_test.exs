defmodule NonprofiteerWeb.FilingSourceControllerTest do
  # async: false — the configured-R2 cases mutate application env (matches object_store_test).
  use NonprofiteerWeb.ConnCase, async: false

  import Nonprofiteer.OrgsFixtures

  @r2_config [
    access_key_id: "AK",
    secret_access_key: "SK",
    bucket: "mirror",
    endpoint: "https://acct.r2.cloudflarestorage.com"
  ]

  defp configure_r2 do
    Application.put_env(:nonprofiteer, :r2, @r2_config)
    Application.put_env(:nonprofiteer, :r2_req_opts, plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.delete_env(:nonprofiteer, :r2)
      Application.delete_env(:nonprofiteer, :r2_req_opts)
    end)
  end

  describe "GET /api/v1/filings/:id/source (mirror dormant / no fetch)" do
    test "404s for an unknown filing id", %{conn: conn} do
      conn = get(conn, "/api/v1/filings/#{Ash.UUID.generate()}/source")
      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "404s for a malformed id instead of crashing", %{conn: conn} do
      conn = get(conn, "/api/v1/filings/not-a-uuid/source")
      assert json_response(conn, 404)
    end

    test "404s for a filing with no mirrored source", %{conn: conn} do
      filing = create_filing(create_org(), %{source_object_id: nil})
      conn = get(conn, "/api/v1/filings/#{filing.id}/source")
      assert json_response(conn, 404)
    end

    test "503s when the filing has a source but the mirror is unconfigured", %{conn: conn} do
      filing = create_filing(create_org(), %{source_object_id: "202001019349300000"})
      conn = get(conn, "/api/v1/filings/#{filing.id}/source")
      assert json_response(conn, 503)["error"] =~ "not configured"
    end
  end

  describe "GET /api/v1/filings/:id/source (mirror configured)" do
    setup do
      configure_r2()
      :ok
    end

    test "200s with the XML body and provenance headers", %{conn: conn} do
      filing = create_filing(create_org(), %{source_object_id: "202001019349300000"})

      Req.Test.stub(__MODULE__, fn r2 ->
        assert r2.method == "GET"
        assert r2.request_path == "/mirror/efile/202001019349300000.xml"
        Plug.Conn.send_resp(r2, 200, "<Return>mirrored</Return>")
      end)

      conn = get(conn, "/api/v1/filings/#{filing.id}/source")

      assert response(conn, 200) == "<Return>mirrored</Return>"
      assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]

      assert get_resp_header(conn, "content-disposition") ==
               [~s(inline; filename="202001019349300000.xml")]

      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    test "404s when the mirror has no such object", %{conn: conn} do
      filing = create_filing(create_org(), %{source_object_id: "202001019349300000"})
      Req.Test.stub(__MODULE__, fn r2 -> Plug.Conn.send_resp(r2, 404, "") end)

      conn = get(conn, "/api/v1/filings/#{filing.id}/source")
      assert json_response(conn, 404)["error"] =~ "not found in mirror"
    end

    test "502s when the mirror errors", %{conn: conn} do
      filing = create_filing(create_org(), %{source_object_id: "202001019349300000"})
      Req.Test.stub(__MODULE__, fn r2 -> Plug.Conn.send_resp(r2, 500, "boom") end)

      conn = get(conn, "/api/v1/filings/#{filing.id}/source")
      assert json_response(conn, 502)
    end
  end
end
