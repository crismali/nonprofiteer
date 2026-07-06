defmodule Nonprofiteer.Ingest.Batch do
  @moduledoc """
  Tolerant fold over an ingest batch, for recording `:partial` runs.

  Ash upserts each row in its own transaction, so a failure partway through a batch leaves the
  earlier rows committed. A plain `Enum.reduce` would let that failure propagate with the
  accumulator lost, forcing the worker to record a `:failure` with a zero count that hides the
  rows that did land. `reduce/3` instead stops at the first row that raises and hands back the
  accumulator built so far *plus* the exception, so the caller can record `:partial` (some rows
  in) versus `:failure` (none) and still reraise for Oban to retry.
  """

  @typedoc "Accumulator threaded through the fold — whatever shape the caller uses."
  @type acc :: term()

  @typedoc "`{:ok, acc}` when every item succeeded, else the failing item's accumulator + error."
  @type result :: {:ok, acc()} | {:error, acc(), Exception.t(), Exception.stacktrace()}

  @doc """
  Reduces `enumerable` with `fun`, stopping at the first item that raises.

  Returns `{:ok, acc}` if every item succeeds, or `{:error, acc, exception, stacktrace}` where
  `acc` reflects the items *before* the one that failed (the failed item is not counted).
  """
  @spec reduce(Enumerable.t(), acc(), (term(), acc() -> acc())) :: result()
  def reduce(enumerable, initial, fun) do
    enumerable
    |> Enum.reduce_while(initial, fn item, acc ->
      try do
        {:cont, fun.(item, acc)}
      rescue
        exception -> {:halt, {:error, acc, exception, __STACKTRACE__}}
      end
    end)
    |> case do
      {:error, _acc, _exception, _stacktrace} = error -> error
      acc -> {:ok, acc}
    end
  end
end
