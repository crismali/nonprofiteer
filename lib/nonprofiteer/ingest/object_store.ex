defmodule Nonprofiteer.Ingest.ObjectStore do
  @moduledoc """
  Minimal S3-compatible client for mirroring source 990 XML into our own object storage (D11).

  Scoped to the one verb the mirror needs: `PUT` an object. Not a general S3 SDK. R2 speaks the
  S3 API, so requests are signed with AWS Signature V4 (`:aws_signature`); the HTTP goes through
  `Req`, matching `Ingest.Client`.

  ## Dormant until configured

  Ships **dormant** — the R2 credentials (`:nonprofiteer, :r2` in `config/runtime.exs`) only land
  at deploy time. Until then `config/0` returns `{:error, :not_configured}` and `put/2`
  short-circuits to it, so dev/test/pre-deploy runs don't attempt a mirror (the parse worker
  turns that into a logged skip rather than a failure). When configured, a successful mirror is
  a precondition for marking a filing ingested, so a re-parse can always read our own copy. No
  credential is ever logged.
  """

  @region "auto"
  @service "s3"

  @typedoc "Resolved R2 connection config — all four values present as non-empty binaries."
  @type t :: %{
          access_key_id: String.t(),
          secret_access_key: String.t(),
          bucket: String.t(),
          endpoint: String.t()
        }

  @doc """
  Uploads `body` to `key` via a signed `PUT`. Returns `:ok` on a 2xx,
  `{:error, {:http_status, status, body}}` on a non-2xx, `{:error, {:transport, reason}}` on a
  transport failure, or `{:error, :not_configured}` when R2 is dormant.
  """
  @spec put(String.t(), iodata()) :: :ok | {:error, :not_configured} | {:error, term()}
  def put(key, body) do
    case config() do
      {:ok, config} ->
        config
        |> signed_request("PUT", key, IO.iodata_to_binary(body))
        |> handle_status()

      {:error, :not_configured} = err ->
        err
    end
  end

  @doc """
  Fetches the object at `key` via a signed `GET`. Returns `{:ok, body}` on a 2xx,
  `{:error, :not_found}` on a 404 (no such mirrored object), `{:error, {:http_status, status,
  body}}` on any other non-2xx, `{:error, {:transport, reason}}` on a transport failure, or
  `{:error, :not_configured}` when R2 is dormant.
  """
  @spec get(String.t()) ::
          {:ok, binary()} | {:error, :not_found} | {:error, :not_configured} | {:error, term()}
  def get(key) do
    case config() do
      {:ok, config} ->
        config
        |> signed_request("GET", key, "")
        |> handle_get()

      {:error, :not_configured} = err ->
        err
    end
  end

  @doc "Whether R2 is configured — the parse worker uses this to require vs. skip the mirror."
  @spec configured?() :: boolean()
  def configured?, do: match?({:ok, _}, config())

  @doc """
  Resolves R2 config from application env (`:nonprofiteer, :r2`). Returns `{:ok, config}` only
  when all four values are present non-empty binaries; otherwise `{:error, :not_configured}`.

      iex> Nonprofiteer.Ingest.ObjectStore.config([])
      {:error, :not_configured}

      iex> Nonprofiteer.Ingest.ObjectStore.config(
      ...>   access_key_id: "AK", secret_access_key: "SK",
      ...>   bucket: "b", endpoint: "https://acct.r2.cloudflarestorage.com/"
      ...> )
      {:ok, %{access_key_id: "AK", secret_access_key: "SK", bucket: "b", endpoint: "https://acct.r2.cloudflarestorage.com"}}
  """
  @spec config(keyword()) :: {:ok, t()} | {:error, :not_configured}
  def config(env \\ Application.get_env(:nonprofiteer, :r2, [])) do
    access_key_id = present(env[:access_key_id])
    secret_access_key = present(env[:secret_access_key])
    bucket = present(env[:bucket])
    endpoint = present(env[:endpoint])

    if access_key_id && secret_access_key && bucket && endpoint do
      {:ok,
       %{
         access_key_id: access_key_id,
         secret_access_key: secret_access_key,
         bucket: bucket,
         endpoint: String.trim_trailing(endpoint, "/")
       }}
    else
      {:error, :not_configured}
    end
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil

  # Builds the object URL, signs with SigV4, and fires it through Req. `uri_encode_path: false`
  # is required for S3/R2 — S3 doesn't double-encode the path segment (unlike other AWS
  # services), so the default `true` yields SignatureDoesNotMatch on any key with a `/`.
  defp signed_request(config, method, key, body) do
    url = "#{config.endpoint}/#{config.bucket}/#{key}"

    headers =
      :aws_signature.sign_v4(
        config.access_key_id,
        config.secret_access_key,
        @region,
        @service,
        :calendar.universal_time(),
        method,
        url,
        [{"host", URI.parse(url).host}],
        body,
        uri_encode_path: false
      )

    Req.request(
      [method: method(method), url: url, headers: headers, body: body, retry: false] ++
        Application.get_env(:nonprofiteer, :r2_req_opts, [])
    )
  end

  defp method("GET"), do: :get
  defp method("PUT"), do: :put

  defp handle_status({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok

  defp handle_status({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http_status, status, body}}

  defp handle_status({:error, reason}), do: {:error, {:transport, reason}}

  # GET shares the signing/transport path but returns the body on success and distinguishes a
  # 404 (object never mirrored) from other non-2xx, so the controller can map it to a clean 404.
  defp handle_get({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, IO.iodata_to_binary(body)}

  defp handle_get({:ok, %Req.Response{status: 404}}), do: {:error, :not_found}

  defp handle_get({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http_status, status, body}}

  defp handle_get({:error, reason}), do: {:error, {:transport, reason}}
end
