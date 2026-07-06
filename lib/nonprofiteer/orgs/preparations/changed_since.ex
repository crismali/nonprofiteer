defmodule Nonprofiteer.Orgs.Preparations.ChangedSince do
  @moduledoc """
  Shared preparation for the resources' `:changed_since` sync-feed read action (D16).

  Bounds the result above by the sync watermark (never serve an in-flight batch's writes) and
  imposes the total order `(updated_at, id)` that keyset pagination rides — so a consumer's
  `page[after]` cursor resumes exactly, and any row re-touched since its last sync re-surfaces
  under its new `updated_at`.
  """
  use Ash.Resource.Preparation

  require Ash.Query

  alias Nonprofiteer.Ingest.SyncWatermark

  @impl Ash.Resource.Preparation
  def prepare(query, _opts, _context) do
    query
    |> Ash.Query.filter(updated_at <= ^SyncWatermark.current())
    |> Ash.Query.sort(updated_at: :asc, id: :asc)
    |> Ash.Query.load(:event_type)
  end
end
