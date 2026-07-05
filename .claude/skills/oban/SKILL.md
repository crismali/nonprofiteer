---
name: oban
description: Oban job conventions for Nonprofiteer's monthly 990/BMF ingest and changed-since sync feed
---

# Oban

Conventions for Oban-based background jobs in this project, driving the ingest + sync-feed design in [ARCHITECTURE.md](../../../docs/ARCHITECTURE.md#data-flow). Oban is a dependency but no jobs are written yet — run its installer/migration before the first worker lands.

> Provenance: adapted from the sibling **ohfec** project's tiered-OpenFEC Oban skill. ohfec's 3-tier (nightly/deadline/on-demand) structure is **not** this project's model — nonprofiteer's ingest is monthly-batch, not user-triggered. The transferable parts (queue separation, run-logging, HTTP-stub testing) are kept; the tier taxonomy is dropped.

## Job structure — monthly batch ingest

The whole pipeline runs on a monthly cadence matching IRS batch drops (per ARCHITECTURE). Two ingest fronts plus serving:

- **BMF ingest** — `Oban.Plugins.Cron` monthly entry. Download the EO BMF extract(s) → upsert `organizations`. The BMF ships as per-state splits (50 + DC + PR + international), so the cron-triggered job should **fan out** into per-extract jobs rather than downloading and parsing everything inline in one job.
- **XML / Part VII ingest** — monthly, but **incremental**: ride the GivingTuesday Data Lake **index files** to enqueue work only for new/changed returns. One coordinator job reads the index and enqueues per-filing (or per-batch) parse jobs; parse jobs mirror the source XML to object storage (D11) and upsert `people`/addresses.
- **Serving** the sync feed is a read path, not an Oban job — don't push feed responses through workers.

Don't do a full monthly sync inline in a single cron job when it can be chunked — fan out so one bad state extract or one malformed return doesn't fail the whole month.

## Queues

- Separate queues by workload so a large BMF/backfill run doesn't starve incremental parse work — e.g. `:ingest_bulk` (BMF, backfill) and `:ingest_incremental` (index-driven parse). Configure concurrency per queue conservatively; downloading/parsing is IO- and CPU-bound, and you don't want a monthly backfill saturating the box.
- Backfill (~3 filing years up front, D9) is a one-time flood — give it its own queue or a low concurrency so it doesn't crowd out the current month's incremental run.

## Workers

```elixir
defmodule Nonprofiteer.Ingest.BmfStateWorker do
  use Oban.Worker, queue: :ingest_bulk, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"state" => state}}) do
    # download the state extract, write an ingest-run row, upsert organizations
  end
end
```

- `max_attempts`: batch/download jobs can afford several retries over a long window; keep it modest and let Oban's backoff handle transient network/IRS-endpoint flakiness.
- **Log every run on both success and failure.** Oban's own job table tracks process exit status, not "did this actually ingest data." Wrap the download + parse + upsert so a job that errors after a partial fetch still records `:partial`/`:failure` on an ingest-run row (build this run-log resource early — it's the guard against silent schema-drift failures called out in [TODO.md](../../../docs/TODO.md)).

## Idempotency & incrementality

- Every ingest job must be **safe to re-run** — monthly cadence + retries mean the same extract/return gets processed more than once. Upserts (via Ash actions, keyed on the source's stable identity) make re-runs converge instead of duplicating rows.
- Incrementality is driven by the Data Lake index, not by scanning every return each month — track what's ingested (index cursor / per-filing marker) and enqueue only new/changed work. Use Oban `unique` on parse jobs so a re-read of the index doesn't double-enqueue an in-flight filing.

## Retry/backoff

- Default Oban exponential backoff is fine for transient IRS/Data Lake endpoint errors — don't hand-roll a separate backoff timer when `max_attempts` + Oban's snooze/backoff already covers it.

## Testing

- Use `Oban.Testing` (`use Oban.Testing, repo: Nonprofiteer.Repo`) with `assert_enqueued`/`perform_job/2` rather than asserting on real scheduling — don't sleep-wait for cron in tests.
- Test the fan-out logic (index → enqueued parse jobs) as a plain unit assertion on what got enqueued, separate from testing a single worker's parse behavior.

### HTTP-stub pattern for download/parse workers

A worker that fetches over HTTP (BMF extract, Data Lake index/XML) is tested by stubbing the HTTP layer with `Req.Test` — have the client read its req options from app env (set per-test, torn down in `on_exit`) so no real network call happens:

```elixir
use Nonprofiteer.DataCase, async: false
use Oban.Testing, repo: Nonprofiteer.Repo

setup do
  Application.put_env(:nonprofiteer, :http_req_opts, plug: {Req.Test, Nonprofiteer.Ingest.Client})
  on_exit(fn -> Application.delete_env(:nonprofiteer, :http_req_opts) end)
end

test "parses a state BMF extract into organizations" do
  Req.Test.stub(Nonprofiteer.Ingest.Client, fn conn ->
    Req.Test.text(conn, File.read!("test/fixtures/bmf/eo_ca_sample.csv"))
  end)

  assert :ok = perform_job(Nonprofiteer.Ingest.BmfStateWorker, %{"state" => "CA"})
end
```

- Use a real captured fixture (`test/fixtures/bmf/*.csv`, `test/fixtures/990/*.xml`) as the stub body — this doubles as the **known-answer fixture** the docs demand for catching Part VII parse drift. Validate parser output against IRSx as the reference.
- Cover the branches that actually bite: the **re-run/idempotency** path (perform twice, assert no duplicate rows), a **malformed/partial** return (assert it logs `:failure`/`:partial`, doesn't corrupt the spine), and the multi-extract fan-out — not just the single happy-path file.

## Gotchas

- Single-node Oban matches a single-BEAM deployment (per ARCHITECTURE) — don't reach for Oban's distributed/global features until that assumption changes.
- Cron jobs need the Cron plugin enabled in the Oban config with the monthly schedule; a worker alone won't self-schedule.
- Object-storage mirroring of source XML (D11) happens inside the parse job — treat a successful mirror as a precondition for marking the filing ingested, so a re-run can always re-parse from our own copy rather than re-hitting the Data Lake.
