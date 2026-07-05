defmodule Nonprofiteer.Credo.Check.DefstructHasType do
  use Credo.Check,
    id: "NONPROF001",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Every module that calls `defstruct` must also declare a matching `@type t()`.

      This is a project-specific rule: because the project leans on Elixir's set-theoretic
      type system instead of Dialyzer (see the `elixir-types` skill), an untyped struct is
      exactly the thing that decision is meant to make the compiler check. The rule applies
      even to a GenServer's internal state struct, not just public-API structs.

          # NOT preferred
          defmodule MyServer do
            defstruct [:capacity, :tokens]
          end

          # preferred
          defmodule MyServer do
            defstruct [:capacity, :tokens]
            @type t() :: %__MODULE__{capacity: pos_integer(), tokens: non_neg_integer()}
          end

      No off-the-shelf check covers this, so it lives as a custom Credo check under
      `.credo/checks/` and is loaded via `requires:` in `.credo.exs`.
      """
    ]

  @moduledoc """
  Credo check enforcing that any module defining a struct also defines `@type t()`.

  See the `:check` explanation for the rationale and examples.
  """

  alias Credo.Code
  alias Credo.IssueMeta

  @doc """
  Runs the check over `source_file`, flagging each `defmodule` that calls `defstruct`
  without a matching `@type t()` (or `@opaque t()`) declaration in the same module body.
  """
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Code.ast()
    |> case do
      {:ok, ast} -> ast
      _ -> SourceFile.ast(source_file)
    end
    |> collect_modules()
    |> Enum.flat_map(&issues_for_module(&1, issue_meta))
  end

  # Walks the AST collecting every `{meta, body_statements}` for a defmodule. Scanning only the
  # direct statements of each module body (not a deep walk) keeps a nested module's `defstruct`
  # from being attributed to its parent.
  defp collect_modules({:defmodule, meta, [_alias, [do: body]]} = ast) do
    [{meta, statements(body)} | collect_children(ast)]
  end

  defp collect_modules(ast), do: collect_children(ast)

  defp collect_children({_form, _meta, args}) when is_list(args),
    do: Enum.flat_map(args, &collect_modules/1)

  defp collect_children({left, right}),
    do: collect_modules(left) ++ collect_modules(right)

  defp collect_children(list) when is_list(list),
    do: Enum.flat_map(list, &collect_modules/1)

  defp collect_children(_), do: []

  defp statements({:__block__, _meta, stmts}), do: stmts
  defp statements(stmt), do: [stmt]

  defp issues_for_module({meta, statements}, issue_meta) do
    if Enum.any?(statements, &defstruct?/1) and not Enum.any?(statements, &type_t?/1) do
      [issue_for(meta, issue_meta)]
    else
      []
    end
  end

  defp defstruct?({:defstruct, _meta, _args}), do: true
  defp defstruct?(_), do: false

  defp type_t?({:@, _meta, [{kind, _, [{:"::", _, [{:t, _, _} | _]} | _]}]})
       when kind in [:type, :opaque],
       do: true

  defp type_t?(_), do: false

  defp issue_for(meta, issue_meta) do
    format_issue(issue_meta,
      message: "Module defines a struct (`defstruct`) but no matching `@type t()`.",
      line_no: meta[:line]
    )
  end
end
