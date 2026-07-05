defmodule Nonprofiteer.Ingest.Client do
  @moduledoc """
  Thin HTTP client for ingest downloads (BMF extracts today, Data Lake index/XML later).

  Reads its `Req` options from application env (`:nonprofiteer, :http_req_opts`) so tests can
  inject a `Req.Test` stub — no ingest worker ever hits the real IRS endpoint under test. In
  dev/prod that env is unset and real requests go out.
  """

  @doc """
  Fetches `url` and returns the raw response body, raising on a transport error or non-2xx
  status. Merged over any configured test/req options.
  """
  @spec fetch!(String.t()) :: binary()
  def fetch!(url) do
    req_opts()
    |> Keyword.put(:url, url)
    |> Req.get!()
    |> Map.fetch!(:body)
  end

  defp req_opts, do: Application.get_env(:nonprofiteer, :http_req_opts, [])
end
