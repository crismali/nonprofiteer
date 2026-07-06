defmodule Nonprofiteer.Ingest.SyncWatermark do
  @moduledoc """
  The upper bound the sync feed serves changes up to (D16).

  D16 bounds the changed-since feed by "the last completed ingest run" so an in-flight batch's
  writes are never served mid-ingest. Because the 990 parse fans out into async Oban jobs with
  no crisp completion instant, that invariant is realized here as a **safety lag**: the feed
  only exposes rows whose `updated_at` is older than `now - lag`. Any write's transaction commits
  within seconds, so a lag of minutes guarantees no half-committed batch leaks — and monthly
  consumers never notice it. Tunable via `:nonprofiteer, :sync_watermark_lag_seconds`.
  """

  # 15 minutes — comfortably past any ingest transaction's commit, invisible at monthly cadence.
  @default_lag_seconds 900

  @doc "The current watermark: the newest `updated_at` the feed is allowed to serve."
  @spec current() :: DateTime.t()
  def current do
    lag = Application.get_env(:nonprofiteer, :sync_watermark_lag_seconds, @default_lag_seconds)
    DateTime.add(DateTime.utc_now(), -lag, :second)
  end
end
