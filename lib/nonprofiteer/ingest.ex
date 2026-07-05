defmodule Nonprofiteer.Ingest do
  @moduledoc """
  The ingest domain — the pipeline that pulls public IRS data into the org spine.

  Groups the durable **ingest-run log** (`Nonprofiteer.Ingest.Run`) that every ingest unit
  writes on success *and* failure. Oban's own job table records process exit, not "did this
  actually ingest correct data" — the run log is the audit trail behind the D8 provenance
  guarantee and the guard against silent schema-drift failures.
  """
  use Ash.Domain, otp_app: :nonprofiteer

  resources do
    resource Nonprofiteer.Ingest.Run
  end
end
