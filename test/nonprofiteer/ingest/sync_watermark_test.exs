defmodule Nonprofiteer.Ingest.SyncWatermarkTest do
  # Reads/writes the `:sync_watermark_lag_seconds` app env, so keep it out of the async pool.
  use ExUnit.Case, async: false

  alias Nonprofiteer.Ingest.SyncWatermark

  setup do
    original = Application.get_env(:nonprofiteer, :sync_watermark_lag_seconds)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:nonprofiteer, :sync_watermark_lag_seconds)
        value -> Application.put_env(:nonprofiteer, :sync_watermark_lag_seconds, value)
      end
    end)
  end

  test "defaults to a 15-minute lag behind now" do
    Application.delete_env(:nonprofiteer, :sync_watermark_lag_seconds)

    lag = DateTime.diff(DateTime.utc_now(), SyncWatermark.current(), :second)

    # 900s default, allowing a couple seconds of test-execution slack.
    assert_in_delta lag, 900, 5
  end

  test "honors a configured lag" do
    Application.put_env(:nonprofiteer, :sync_watermark_lag_seconds, 60)

    lag = DateTime.diff(DateTime.utc_now(), SyncWatermark.current(), :second)

    assert_in_delta lag, 60, 5
  end

  test "a zero lag puts the watermark at (approximately) now" do
    Application.put_env(:nonprofiteer, :sync_watermark_lag_seconds, 0)

    assert DateTime.diff(DateTime.utc_now(), SyncWatermark.current(), :second) |> abs() <= 5
  end
end
