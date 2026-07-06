defmodule Nonprofiteer.Ingest.RunTest do
  use Nonprofiteer.DataCase, async: true

  alias Nonprofiteer.Ingest.Run

  defp create_run(attrs) do
    Run |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  test "a clean run reads clean — counts default to 0" do
    run = create_run(%{source: :bmf, extract_id: "CA", status: :success})

    assert run.row_count == 0
    assert run.orphan_skipped_count == 0
    assert is_nil(run.error_message)
  end

  test "records counts and a failure line" do
    run =
      create_run(%{
        source: :efile_990,
        status: :partial,
        row_count: 12,
        orphan_skipped_count: 3,
        error_message: "boom"
      })

    assert run.row_count == 12
    assert run.orphan_skipped_count == 3
    assert run.status == :partial
    assert run.error_message == "boom"
  end

  test "source and status are required" do
    assert_raise Ash.Error.Invalid, fn -> create_run(%{status: :success}) end
    assert_raise Ash.Error.Invalid, fn -> create_run(%{source: :bmf}) end
  end

  test "record!/1 writes an audit row from a bare attribute map" do
    run = Run.record!(%{source: :bmf, extract_id: "CA", status: :success, row_count: 7})

    assert run.id
    assert run.source == :bmf
    assert run.row_count == 7
  end

  test "source and status are constrained to their allowed values" do
    assert_raise Ash.Error.Invalid, fn ->
      create_run(%{source: :not_a_source, status: :success})
    end

    assert_raise Ash.Error.Invalid, fn ->
      create_run(%{source: :bmf, status: :not_a_status})
    end
  end
end
