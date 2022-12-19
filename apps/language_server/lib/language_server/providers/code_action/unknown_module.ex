defmodule ElixirLS.LanguageServer.Providers.CodeAction.UnknownModule do
  @behaviour ElixirLS.LanguageServer.Providers.CodeAction

  use ElixirLS.LanguageServer.Protocol

  alias ElixirLS.LanguageServer.Providers.CodeAction.Helpers
  alias ElixirLS.LanguageServer.SourceFile
  alias ElixirSense.Core.Parser

  @undefined_module "(.*) is undefined \\(module (.*) is not available or is yet to be defined\\)"
  @unknown_struct "\\(CompileError\\) (.*).__struct__/(.*) is undefined, cannot expand struct (.*)."

  @number_of_candidates_to_start_filtering_at 2

  @impl true
  def pattern, do: Regex.compile!("(#{@undefined_module})|(#{@unknown_struct})")

  @impl true
  def get_actions(uri, %{"message" => message, "range" => range} = diagnostic, source_file) do
    module_name = parse_message(message)

    active_module_name =
      source_file
      |> Helpers.active_module(range)
      |> Atom.to_string()
      |> String.replace_leading("Elixir.", "")

    {:ok, ast, _source} = Parser.string_to_ast(source_file.text, 5, 0)

    case get_module_definition(ast, active_module_name) do
      {:ok, module_ast} ->
        start_line = Helpers.start_line_from_range(range)

        source_lines = SourceFile.lines(source_file)
        source_line = Enum.at(source_lines, start_line)

        {prefix, suffix, insert_line} = calculate_alias_location(module_ast, source_lines)

        module_name
        |> find_full_module_name_candidates(module_name, active_module_name)
        |> Enum.map(fn full_module_name ->
          alias_actions =
            generate_alias_actions(
              uri,
              full_module_name,
              diagnostic,
              prefix,
              suffix,
              insert_line
            )

          replace_actions =
            generate_replace_actions(
              uri,
              full_module_name,
              diagnostic,
              source_line,
              start_line,
              module_name
            )

          alias_actions ++ replace_actions
        end)

      _error ->
        []
    end
  end

  defp parse_message(message) do
    undefined_module_matches =
      @undefined_module
      |> Regex.compile!()
      |> Regex.run(message)

    if undefined_module_matches != nil do
      [_, _, module_name] = undefined_module_matches
      module_name
    else
      [_, module_name | _] =
        @unknown_struct
        |> Regex.compile!()
        |> Regex.run(message)

      module_name
    end
  end

  # Returns only the current module if they are nested in one file.
  defp get_module_definition(ast, module_name_as_string) do
    module_name =
      module_name_as_string
      |> String.split(".")
      |> Enum.map(&String.to_existing_atom/1)

    resulting_ast =
      Macro.traverse(
        ast,
        {nil, []},
        fn
          {:defmodule, _meta, [{:__aliases__, _aliases_meta, alias_module_name} | _]} = ast,
          {nil, parent_module_name} ->
            alias_module_name = parent_module_name ++ alias_module_name

            if alias_module_name == module_name do
              {ast, {ast, parent_module_name}}
            else
              {ast, {nil, alias_module_name}}
            end

          ast_node, acc ->
            {ast_node, acc}
        end,
        fn
          {:defmodule, _meta, [{:__aliases__, _aliases_meta, alias_module_name} | _]} = ast,
          {nil, parent_module_name} ->
            alias_module_name =
              parent_module_name
              |> Enum.reverse()
              |> then(&(&1 -- Enum.reverse(alias_module_name)))
              |> Enum.reverse()

            {ast, {nil, alias_module_name}}

          ast_node, acc ->
            {ast_node, acc}
        end
      )

    case resulting_ast do
      {_, {module_ast, _}} when module_ast != nil -> {:ok, module_ast}
      _ -> {:error, :not_found}
    end
  end

  # these lines have offset +1 (we enumerate lines in the program from 0, but lines in ast are from 1)
  # so don't need to add 1
  defp calculate_alias_location({:defmodule, _, module_body_ast} = module_ast, source_lines) do
    case Enum.reduce_while(
           [:alias, :require, :import, :use, :behaviour, :moduledoc],
           nil,
           fn ast_node_type, _acc ->
             case calculate_alias_location_based_on(module_body_ast, ast_node_type) do
               nil -> {:cont, nil}
               nodes -> {:halt, nodes}
             end
           end
         ) do
      nil ->
        {last_node, next_node} = calculate_alias_location_based_on(module_ast, :defmodule)
        calculate_prefix_suffix_insert_line(last_node, next_node, source_lines)

      {last_node, next_node} ->
        calculate_prefix_suffix_insert_line(last_node, next_node, source_lines)
    end
  end

  defp calculate_alias_location_based_on(module_ast, :defmodule) do
    defmodule_line = get_metadata(module_ast, :line)

    {_, {last_node, next_node}} =
      Macro.prewalk(module_ast, nil, fn
        {_marker, _meta, _body} = ast, nil ->
          current_line = get_metadata(ast, :line)

          if current_line > defmodule_line do
            {ast, {module_ast, ast}}
          else
            {ast, nil}
          end

        ast, acc ->
          {ast, acc}
      end)

    {last_node, next_node}
  end

  defp calculate_alias_location_based_on(module_body_ast, ast_node_type)
       when ast_node_type in [:behaviour, :moduledoc] do
    case Macro.prewalk(module_body_ast, nil, fn
           {:@, _meta, [{^ast_node_type, _inner_meta, _body}]} = ast, nil ->
             {[], {ast, nil}}

           ast, {last_node, nil} ->
             {ast, {last_node, ast}}

           {:defmodule, _meta, _body}, acc ->
             {[], acc}

           ast, acc ->
             {ast, acc}
         end) do
      {_, {last_node, next_node}} -> {last_node, next_node}
      _asts -> nil
    end
  end

  defp calculate_alias_location_based_on(module_body_ast, ast_node_type) do
    case Macro.prewalk(module_body_ast, nil, fn
           {^ast_node_type, _meta, _body} = ast, _acc ->
             {[], {ast, nil}}

           ast, {last_node, nil} ->
             {ast, {last_node, ast}}

           {:defmodule, _meta, _body}, acc ->
             {[], acc}

           ast, acc ->
             {ast, acc}
         end) do
      {_, {last_node, next_node}} -> {last_node, next_node}
      _asts -> nil
    end
  end

  defp calculate_prefix_suffix_insert_line(last_node, next_node, source_lines) do
    last_node_line_number = get_metadata(last_node, :line)

    next_node_line_number = get_metadata(next_node, :line)
    next_node_line = Enum.at(source_lines, next_node_line_number - 1)

    trimmed_length =
      next_node_line
      |> String.trim_leading()
      |> String.length()

    alias_column = String.length(next_node_line) - trimmed_length
    alias_prefix = String.duplicate(" ", alias_column)

    alias_suffix =
      if source_lines |> Enum.at(next_node_line_number - 2) |> String.trim() |> String.length() >
           0 do
        "\n\n"
      else
        "\n"
      end

    case last_node do
      {:alias, _meta, _body} ->
        {alias_prefix, alias_suffix, last_node_line_number}

      {:require, _meta, _body} ->
        {"\n" <> alias_prefix, alias_suffix, last_node_line_number}

      {:import, _meta, _body} ->
        {"\n" <> alias_prefix, alias_suffix, last_node_line_number}

      {:use, _meta, _body} ->
        {"\n" <> alias_prefix, alias_suffix, last_node_line_number}

      {:@, _meta, [{:behaviour, _inner_meta, _body}]} ->
        {"\n" <> alias_prefix, alias_suffix, last_node_line_number}

      {:@, _meta, [{:moduledoc, _inner_meta, _body}]} ->
        insert_line =
          if source_lines |> Enum.at(next_node_line_number - 2) |> String.contains?("\"") do
            next_node_line_number - 1
          else
            next_node_line_number - 2
          end

        {"\n" <> alias_prefix, alias_suffix, insert_line}

      {:defmodule, _meta, _body} ->
        {alias_prefix, alias_suffix, last_node_line_number}
    end
  end

  defp get_metadata({_, metadata, _}, key) do
    Keyword.get(metadata, key)
  end

  defp find_full_module_name_candidates("", _original_module_name_as_string, _active_module_name) do
    []
  end

  defp find_full_module_name_candidates(
         module_name_as_string,
         original_module_name_as_string,
         active_module_name
       ) do
    candidates =
      ElixirSense.all_modules()
      |> Enum.filter(&String.ends_with?(&1, "." <> module_name_as_string))
      |> Enum.reject(&(&1 == original_module_name_as_string))
      |> reject_foreign_module_names_when_many_matches(active_module_name)

    if candidates == [] do
      module_name_with_first_part_removed =
        String.split(module_name_as_string, ".")
        |> Enum.drop(1)
        |> Enum.join(".")

      find_full_module_name_candidates(
        module_name_with_first_part_removed,
        original_module_name_as_string,
        active_module_name
      )
    else
      candidates
    end
  end

  defp reject_foreign_module_names_when_many_matches(
         full_module_name_candidates,
         active_module_name
       ) do
    active_namespace =
      active_module_name
      |> String.split(".")
      |> List.first()

    filtered_candidates =
      Enum.filter(full_module_name_candidates, &String.starts_with?(&1, active_namespace))

    if Enum.count(filtered_candidates) >= @number_of_candidates_to_start_filtering_at do
      filtered_candidates
    else
      full_module_name_candidates
    end
  end

  defp generate_alias_actions(uri, full_module_name, diagnostics, prefix, suffix, insert_line) do
    [
      %{
        "title" => "Add alias #{full_module_name}",
        "kind" => "quickfix",
        "diagnostics" => [diagnostics],
        "isPreferred" => true,
        "edit" => %{
          "changes" => %{
            uri => [
              %{
                "range" =>
                  range(
                    insert_line,
                    0,
                    insert_line,
                    0
                  ),
                "newText" => "#{prefix}alias #{full_module_name}#{suffix}"
              }
            ]
          }
        }
      }
    ]
  end

  defp generate_replace_actions(
         uri,
         full_module_name,
         diagnostics,
         source_line,
         start_line,
         module_name
       ) do
    [
      %{
        "title" => "Replace with #{full_module_name}",
        "kind" => "quickfix",
        "diagnostics" => [diagnostics],
        "edit" => %{
          "changes" => %{
            uri => [
              %{
                "range" =>
                  range(
                    start_line,
                    0,
                    start_line,
                    String.length(source_line)
                  ),
                "newText" => String.replace(source_line, module_name, full_module_name)
              }
            ]
          }
        }
      }
    ]
  end
end
