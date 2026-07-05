defmodule Nonprofiteer.Ingest.Run do
  @moduledoc """
  A durable record of one ingest unit — one BMF extract download+upsert, and later one 990
  parse batch.

  Written on **both** success and failure so a job that errors after a partial fetch still
  leaves an audit row (Oban's job table only tracks process exit, not data correctness). The
  row counts and `orphan_skipped_count` are the observable surface for catching silent
  schema-drift regressions the ingest docs warn about — a run that "succeeds" but writes zero
  rows is a red flag, not an empty success.
  """
  use Ash.Resource,
    otp_app: :nonprofiteer,
    domain: Nonprofiteer.Ingest,
    data_layer: AshPostgres.DataLayer

  @type t :: %__MODULE__{}

  postgres do
    table "ingest_runs"
    repo Nonprofiteer.Repo

    custom_indexes do
      index [:source, :extract_id]
      index [:inserted_at]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source, :atom do
      public? true
      allow_nil? false
      constraints one_of: [:bmf, :efile_990]
      description "Which ingest pipeline produced this run."
    end

    attribute :extract_id, :string do
      public? true

      description """
      Which slice of the source this run covered — for BMF the state/region extract id
      (e.g. "eo1", "CA"); for 990 a parse-batch id.
      """
    end

    attribute :status, :atom do
      public? true
      allow_nil? false
      constraints one_of: [:success, :partial, :failure]
      description "Outcome. `:partial` = some rows ingested before an error stopped the run."
    end

    attribute :row_count, :integer do
      public? true
      allow_nil? false
      default 0
      description "Rows successfully upserted this run."
    end

    attribute :orphan_skipped_count, :integer do
      public? true
      allow_nil? false
      default 0

      description """
      Rows deliberately skipped for lacking a parent to attach to (e.g. a Part VII person whose
      org isn't in the spine yet). Defaults to 0 so a clean run reads clean.
      """
    end

    attribute :error_message, :string do
      public? true
      description "Decisive failure line when `status` is `:partial`/`:failure`."
    end

    timestamps()
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
