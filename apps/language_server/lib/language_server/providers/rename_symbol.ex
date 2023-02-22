defmodule ElixirLS.LanguageServer.Providers.RenameSymbol do
  use ElixirLS.LanguageServer.Protocol

  alias ElixirLS.LanguageServer.SourceFile
  alias ElixirLS.LanguageServer.Tracer

  alias ElixirSense.Core.Parser
  alias ElixirSense.Location

  alias SourceFile.Path

  def prepare(_uri, position, source_file) do
    with {{start_line, start_col}, {end_line, end_col}, identifier} <-
           surround_context(source_file.text, position) do
      result = %{
        range: range(start_line - 1, start_col - 1, end_line - 1, end_col - 1),
        placeholder: to_string(identifier)
      }

      {:ok, result}
    else
      _ ->
        # Not a variable or function call, skipping
        {:ok, nil}
    end
  end

  def rename(uri, position, new_name, source_file) do
    %{"character" => column, "line" => line_number} = position

    trace = Tracer.get_trace()

    with {_begin, _end, identifier} <- surround_context(source_file.text, position),
         %Location{} = definition <-
           ElixirSense.definition(source_file.text, line_number + 1, column + 1),
         references <-
           ElixirSense.references(source_file.text, line_number + 1, column + 1, trace) do
      definition_text_edits =
        case definition do
          # definition in the current file
          %{file: nil, type: :function} ->
            function_definition_to_text_edit(
              definition,
              source_file.text,
              identifier,
              uri,
              new_name
            )

          # definition in a different file
          %{file: file_path, type: :function} ->
            file_uri = Path.to_uri(file_path)

            function_definition_to_text_edit(
              definition,
              definition,
              identifier,
              file_uri,
              new_name
            )

          # variable
          _variable ->
            variable_definition_to_text_edit(definition, uri, identifier, new_name)
        end

      refactors =
        references
        |> references_to_text_edits(new_name, uri)
        |> then(fn references_text_edits -> references_text_edits ++ definition_text_edits end)
        |> Enum.uniq()
        |> create_workspace_edit()

      {:ok, refactors}
    else
      _ -> {:ok, []}
    end
  end

  defp surround_context(text, %{"character" => character, "line" => line}) do
    surround_context(text, line + 1, character + 1) || surround_context(text, line + 1, character)
  end

  defp surround_context(text, line, character) do
    with %{begin: begin, end: the_end, context: context} <-
           Code.Fragment.surround_context(text, {line, character}) do
      case context do
        {context, identifier} when context in [:local_or_var, :local_arity, :local_call] ->
          {begin, the_end, identifier}

        {:dot, _, identifier} ->
          {begin, the_end, identifier}

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  defp function_definition_to_text_edit(definition, file, identifier, uri, new_name) do
    definition_position = {definition.line, definition.column}

    identifier_lenth =
      identifier
      |> to_string()
      |> String.length()

    parsed_source_code = parse_definition_file(file)

    parsed_source_code.mods_funs_to_positions
    |> Map.filter(fn {{_module, function_name, arity}, %{positions: positions}} ->
      Atom.to_charlist(function_name) == identifier and not is_nil(arity) and
        definition_position in positions
    end)
    |> Enum.flat_map(fn {_, %{positions: positions}} -> positions end)
    |> Enum.uniq()
    |> Enum.map(fn {line_number, column} ->
      range = range(line_number - 1, column - 1, line_number - 1, column + identifier_lenth - 1)

      {uri, %{"range" => range, "newText" => new_name}}
    end)
  end

  defp parse_definition_file(%{file: file}) do
    Parser.parse_file(file, true, true, nil)
  end

  defp parse_definition_file(source_text) when is_binary(source_text) do
    Parser.parse_string(source_text, true, true, nil)
  end

  defp variable_definition_to_text_edit(definition, uri, identifier, new_name) do
    %{line: line_number, column: column} = definition

    identifier_lenth =
      identifier
      |> to_string()
      |> String.length()

    range = range(line_number - 1, column - 1, line_number - 1, column + identifier_lenth - 1)

    [{uri, %{"range" => range, "newText" => new_name}}]
  end

  defp references_to_text_edits(references, new_name, start_uri) do
    Enum.map(references, fn %{range: %{start: start_position, end: end_position}, uri: uri} ->
      uri = maybe_format_uri(uri, start_uri)

      %{line: start_line, column: start_column} = start_position
      %{line: end_line, column: end_column} = end_position

      range = range(start_line - 1, start_column - 1, end_line - 1, end_column - 1)

      {uri, %{"range" => range, "newText" => new_name}}
    end)
  end

  defp maybe_format_uri(nil, start_uri), do: start_uri
  defp maybe_format_uri(uri, _start_uri), do: "file://" <> uri

  defp create_workspace_edit(text_edits) do
    %{"changes" => Enum.group_by(text_edits, &elem(&1, 0), &elem(&1, 1))}
  end
end
