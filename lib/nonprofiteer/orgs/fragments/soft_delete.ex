defmodule Nonprofiteer.Orgs.Fragments.SoftDelete do
  @moduledoc """
  Soft-delete + sync-event machinery shared by the history-bearing resources (D10): the
  `tombstoned_at` marker, the `:tombstone` action that sets it, and the `event_type`
  calculation that derives a row's sync-feed status from its tombstone/supersede state.

  Used by `Organization`/`Filing`/`Person`. The `superseded_by` self-reference the `event_type`
  reads stays defined on each resource — a fragment's `__MODULE__` resolves to the fragment,
  not the resource, so it can't live here — but it exists in the merged resource, so the
  `superseded_by_id` reference below resolves fine.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

  attributes do
    # Soft-delete marker (D10) — set by the `:tombstone` action; history is never hard-deleted.
    attribute :tombstoned_at, :utc_datetime_usec do
      public? true
      description "Timestamp at which this record was withdrawn; null while the record is live."
    end
  end

  actions do
    # Soft-delete: mark the record withdrawn without destroying history (D10).
    update :tombstone do
      accept []
      require_atomic? false
      change set_attribute(:tombstoned_at, &DateTime.utc_now/0)
    end
  end

  # Derived from tombstone/supersede state (D10/D16); the sync feed emits it per record.
  calculations do
    calculate :event_type,
              :atom,
              expr(
                cond do
                  not is_nil(tombstoned_at) -> :tombstoned
                  not is_nil(superseded_by_id) -> :superseded
                  true -> :upsert
                end
              ) do
      public? true
      constraints one_of: [:upsert, :superseded, :tombstoned]

      description """
      This record's status in the sync feed: `upsert` (created or changed), `superseded`
      (replaced by a newer version of the same record), or `tombstoned` (withdrawn).
      """
    end
  end
end
