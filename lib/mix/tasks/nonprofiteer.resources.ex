defmodule Mix.Tasks.Nonprofiteer.Resources do
  @shortdoc "Prints an Ash resource's shape (attributes, relationships, actions, …) in one command"

  @moduledoc """
  Introspects a compiled Ash resource and prints its shape — attributes (+types), relationships
  (+destinations), actions, identities, calculations, aggregates, and primary key — so a
  resource's structure can be read in one command instead of opening its source file (and the
  files it relates to).

      mix nonprofiteer.resources Organization
      mix nonprofiteer.resources Nonprofiteer.Orgs.Address

  With no argument it lists every registered resource grouped by domain. With an unknown name it
  reports not-found and fuzzy-lists near matches.

  Reads the **compiled** resource via `Ash.Resource.Info` rather than re-parsing the DSL source,
  so what it prints is what the resource actually compiled to (defaults applied, fragments
  expanded), not what the source text appears to say. Resources are enumerated from the
  configured domains (`:nonprofiteer, :ash_domains`), so this covers every domain, not just one
  namespace.
  """

  use Mix.Task

  # Pure introspection over compiled modules + config; no Repo/app boot needed.
  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    resources = all_resources()

    case args do
      [name | _] -> print_resource(name, resources)
      [] -> list_resources(resources)
    end

    :ok
  end

  # All resources across every configured domain, as `{module, "ShortName"}` pairs.
  defp all_resources do
    :nonprofiteer
    |> Application.get_env(:ash_domains, [])
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.uniq()
    |> Enum.map(&{&1, short_name(&1)})
  end

  defp short_name(module), do: module |> Module.split() |> List.last()

  defp print_resource(name, resources) do
    query = String.downcase(name)

    match =
      Enum.find(resources, fn {module, short} ->
        String.downcase(short) == query or String.downcase(inspect(module)) == query
      end)

    case match do
      {module, _short} -> print_resource_info(module)
      nil -> print_not_found(name, resources)
    end
  end

  defp print_not_found(name, resources) do
    Mix.shell().error("No resource named #{inspect(name)}.\n")
    query = String.downcase(name)

    matches =
      resources
      |> Enum.filter(fn {_module, short} -> String.contains?(String.downcase(short), query) end)
      |> Enum.map(&elem(&1, 0))

    case matches do
      [] ->
        Mix.shell().info("No matching resources. Run with no argument to list all.")

      _ ->
        Mix.shell().info("Matching resources (#{length(matches)}):")
        matches |> Enum.sort() |> Enum.each(&Mix.shell().info("  #{inspect(&1)}"))
    end
  end

  defp list_resources(resources) do
    Mix.shell().info("Registered resources (#{length(resources)}):")

    resources
    |> Enum.group_by(fn {module, _short} -> Ash.Resource.Info.domain(module) end)
    |> Enum.sort_by(fn {domain, _} -> inspect(domain) end)
    |> Enum.each(fn {domain, group} ->
      Mix.shell().info("\n  #{inspect(domain)}:")

      group
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()
      |> Enum.each(&Mix.shell().info("    #{inspect(&1)}"))
    end)
  end

  defp print_resource_info(module) do
    Mix.shell().info("== #{inspect(module)} ==")
    Mix.shell().info("domain:     #{inspect(Ash.Resource.Info.domain(module))}")
    Mix.shell().info("data layer: #{describe_data_layer(module)}")
    Mix.shell().info("primary key: #{Enum.join(Ash.Resource.Info.primary_key(module), ", ")}")

    print_attributes(module)
    print_relationships(module)
    print_actions(module)
    print_identities(module)
    print_calculations(module)
    print_aggregates(module)
  end

  defp describe_data_layer(module) do
    case Ash.Resource.Info.data_layer(module) do
      AshPostgres.DataLayer ->
        "AshPostgres → table #{inspect(AshPostgres.DataLayer.Info.table(module))}"

      other ->
        inspect(other)
    end
  end

  defp print_attributes(module) do
    attributes = Ash.Resource.Info.attributes(module)
    print_header("attributes", length(attributes))

    Enum.each(attributes, fn attr ->
      Mix.shell().info("  #{attr.name}: #{describe_type(attr.type)}#{attr_flags(attr)}")
    end)
  end

  defp attr_flags(attr) do
    [
      attr.primary_key? && "pk",
      not attr.primary_key? && not attr.allow_nil? && "required",
      not attr.public? && "private",
      not is_nil(attr.default) && "default #{inspect(attr.default)}"
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> ""
      flags -> " (#{Enum.join(flags, ", ")})"
    end
  end

  defp print_relationships(module) do
    relationships = Ash.Resource.Info.relationships(module)
    print_header("relationships", length(relationships))

    Enum.each(relationships, fn rel ->
      Mix.shell().info(
        "  #{rel.type} #{rel.name} → #{inspect(rel.destination)} " <>
          "(#{rel.source_attribute} → #{rel.destination_attribute})"
      )
    end)
  end

  defp print_actions(module) do
    actions = Ash.Resource.Info.actions(module)
    print_header("actions", length(actions))

    Enum.each(actions, fn action ->
      primary = if action.primary?, do: " (primary)", else: ""
      Mix.shell().info("  #{action.type} #{action.name}#{primary}#{action_args(action)}")
    end)
  end

  defp action_args(%{arguments: []}), do: ""

  defp action_args(%{arguments: arguments}) do
    args = Enum.map_join(arguments, ", ", &"#{&1.name}: #{describe_type(&1.type)}")
    " — args: #{args}"
  end

  defp action_args(_action), do: ""

  defp print_identities(module) do
    identities = Ash.Resource.Info.identities(module)
    print_header("identities", length(identities))

    Enum.each(identities, fn identity ->
      Mix.shell().info("  #{identity.name}: #{Enum.join(identity.keys, ", ")}")
    end)
  end

  defp print_calculations(module) do
    calculations = Ash.Resource.Info.calculations(module)
    print_header("calculations", length(calculations))

    Enum.each(calculations, fn calc ->
      Mix.shell().info("  #{calc.name}: #{describe_type(calc.type)}")
    end)
  end

  defp print_aggregates(module) do
    aggregates = Ash.Resource.Info.aggregates(module)
    print_header("aggregates", length(aggregates))

    Enum.each(aggregates, fn agg ->
      path = agg.relationship_path |> Enum.join(".")
      field = if agg.field, do: ".#{agg.field}", else: ""
      Mix.shell().info("  #{agg.name}: #{agg.kind} over #{path}#{field}")
    end)
  end

  # Always prints the section count (so an empty "0" section is visibly accounted for, not absent).
  defp print_header(label, count), do: Mix.shell().info("\n#{label} (#{count}):")

  # Render an Ash type as its short atom (`Ash.Type.String` → `:string`), recursing into
  # `{:array, inner}`. Falls back to the inspected module name for types without a short alias.
  defp describe_type({:array, inner}), do: "array<#{describe_type(inner)}>"

  defp describe_type(type) do
    case Map.get(short_type_names(), type) do
      nil -> type |> inspect() |> String.replace_prefix("Ash.Type.", "")
      short -> inspect(short)
    end
  end

  defp short_type_names do
    Map.new(Ash.Type.short_names(), fn {short, module} -> {module, short} end)
  end
end
