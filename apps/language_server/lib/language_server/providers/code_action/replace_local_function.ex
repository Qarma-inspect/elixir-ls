defmodule ElixirLS.LanguageServer.Providers.CodeAction.ReplaceLocalFunction do
  use ElixirLS.LanguageServer.Protocol

  alias ElixirLS.LanguageServer.Providers.CodeAction.Helpers
  alias ElixirLS.LanguageServer.SourceFile
  alias ElixirSense.Core.{Metadata, Parser, State}

  @default_env State.default_env()

  @spec pattern :: Regex.t()
  def pattern, do: ~r/undefined function ([^\/]*)\/([0-9]*)/

  def get_actions(uri, %{"message" => message, "range" => range}, source_file) do
    [_, function_name, _function_arity] = Regex.run(pattern(), message)

    active_module = active_module(source_file, range)

    start_line = Helpers.start_line_from_range(range)

    source_line =
      source_file
      |> SourceFile.lines()
      |> Enum.at(start_line)

    function_name
    |> extract_local_function_candidates(source_file, active_module)
    |> Enum.reject(&(&1 == function_name))
    |> Enum.map(fn candidate_name ->
      title = "Replace unknown function with '#{candidate_name}'"
      range = range(start_line, 0, start_line, String.length(source_line))
      new_text = do_replace_local_function(source_line, function_name, candidate_name)

      Helpers.create_quickfix(title, uri, range, new_text)
    end)
  end

  defp active_module(source_file, range) do
    start_line = Helpers.start_line_from_range(range)
    metadata = Parser.parse_string(source_file.text, true, true, 1)

    %State.Env{module: active_module} = get_env_from_line(metadata, start_line + 1)

    active_module
  end

  defp get_env_from_line(metadata, line) when line >= 0 do
    case Metadata.get_env(metadata, line) do
      @default_env -> get_env_from_line(metadata, line - 1)
      env -> env
    end
  end

  defp get_env_from_line(_metadata, _line) do
    @default_env
  end

  defp extract_local_function_candidates(function_name, source_file, active_module) do
    %Metadata{mods_funs_to_positions: module_functions} =
      Parser.parse_string(source_file.text, true, true, 1)

    module_functions
    |> Enum.filter(fn {{module, _function, _arity}, _} -> module == active_module end)
    |> Enum.map(fn {{_module, function, _arity}, _} -> Atom.to_string(function) end)
    |> Enum.uniq()
    |> Enum.filter(fn candidate_function_name ->
      String.bag_distance(function_name, candidate_function_name) > 0.4
    end)
  end

  defp do_replace_local_function(source_line, function_name, candidate_name) do
    {:ok, pattern_call} = Regex.compile("(?<![[:alnum:]._])#{Regex.escape(function_name)}[(]")
    {:ok, pattern_pass} = Regex.compile("&#{Regex.escape(function_name)}/")

    source_line
    |> String.replace(pattern_call, candidate_name <> "(")
    |> String.replace(pattern_pass, "&#{candidate_name}/")
  end
end
