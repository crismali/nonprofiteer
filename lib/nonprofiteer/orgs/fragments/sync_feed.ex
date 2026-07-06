defmodule Nonprofiteer.Orgs.Fragments.SyncFeed do
  @moduledoc """
  The `:changed_since` read action shared by every sync-feed resource (D16/D17).

  Identical across `Organization`/`Address`/`Filing`/`Person`, so it lives here as a Spark DSL
  fragment instead of being copy-pasted into each. The watermark bound, keyset order, and
  `event_type` load all live in the `ChangedSince` preparation.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

  actions do
    read :changed_since do
      description "Sync feed (D16): records changed up to the watermark, keyset-ordered."
      pagination keyset?: true, default_limit: 200, max_page_size: 2000, required?: false
      prepare Nonprofiteer.Orgs.Preparations.ChangedSince
    end
  end
end
