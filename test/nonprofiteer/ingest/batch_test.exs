defmodule Nonprofiteer.Ingest.BatchTest do
  use ExUnit.Case, async: true

  alias Nonprofiteer.Ingest.Batch

  test "returns {:ok, acc} when every item succeeds" do
    assert {:ok, 6} = Batch.reduce([1, 2, 3], 0, fn n, sum -> sum + n end)
  end

  test "stops at the first raising item and returns the accumulator built so far" do
    fun = fn n, sum ->
      if n == 3, do: raise("boom")
      sum + n
    end

    assert {:error, acc, exception, stacktrace} = Batch.reduce([1, 2, 3, 4], 0, fun)
    # 1 + 2 accumulated before item 3 raised; item 3 (and 4) are not counted.
    assert acc == 3
    assert %RuntimeError{message: "boom"} = exception
    assert is_list(stacktrace)
  end

  test "a first-item failure yields the initial accumulator" do
    assert {:error, 0, _exception, _stacktrace} =
             Batch.reduce([1, 2], 0, fn _n, _sum -> raise("nope") end)
  end

  test "an empty enumerable is trivially {:ok, initial}" do
    assert {:ok, :untouched} = Batch.reduce([], :untouched, fn _n, _acc -> raise("unreached") end)
  end
end
