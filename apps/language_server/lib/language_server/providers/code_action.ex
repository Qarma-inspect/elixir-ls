defmodule ElixirLS.LanguageServer.Providers.CodeAction do
  use ElixirLS.LanguageServer.Protocol

  alias ElixirLS.LanguageServer.SourceFile
  alias ElixirSense.Core.{Metadata, Parser, State}

  @variable_is_unused ~r/variable "(.*)" is unused/
  @unknown_remote_function ~r/(.*)\/(.*) is undefined or private. .*:\n(.*)/s
  @unknown_local_function ~r/undefined function ([^\/]*)\/([0-9]*)/

  def code_actions(uri, diagnostics, source_file) do
    actions =
      diagnostics
      |> Enum.map(fn diagnostic -> actions(uri, diagnostic, source_file) end)
      |> List.flatten()

    {:ok, actions}
  end

  defp actions(uri, %{"message" => message} = diagnostic, source_file) do
    [
      {@variable_is_unused, &prefix_with_underscore/3},
      {@unknown_remote_function, &replace_unknown_remote_function/3},
      {@unknown_local_function, &replace_unknown_local_function/3}
    ]
    |> Enum.filter(fn {r, _fun} -> String.match?(message, r) end)
    |> Enum.map(fn {_r, fun} -> fun.(uri, diagnostic, source_file) end)
  end

  defp prefix_with_underscore(uri, %{"message" => message, "range" => range}, source_file) do
    [_, variable] = Regex.run(@variable_is_unused, message)

    start_line = start_line_from_range(range)

    source_line =
      source_file
      |> SourceFile.lines()
      |> Enum.at(start_line)

    pattern = Regex.compile!("(?<![[:alnum:]._])#{Regex.escape(variable)}(?![[:alnum:]._])")

    if pattern |> Regex.scan(source_line) |> length() == 1 do
      title = "Add '_' to unused variable"
      range = range(start_line, 0, start_line, String.length(source_line))
      new_text = String.replace(source_line, pattern, "_" <> variable)

      create_quickfix(title, uri, range, new_text)
    else
      []
    end
  end

  defp replace_unknown_remote_function(
         uri,
         %{"message" => message, "range" => range},
         source_file
       ) do
    [_, full_function_name, _function_arity, candidates_string] =
      Regex.run(@unknown_remote_function, message)

    function_module =
      full_function_name
      |> String.split(".")
      |> Enum.slice(0..-2//1)
      |> Enum.join(".")

    start_line = start_line_from_range(range)

    source_line =
      source_file
      |> SourceFile.lines()
      |> Enum.at(start_line)

    candidates_string
    |> parse_candidates_string()
    |> Enum.map(&(function_module <> "." <> &1))
    |> Enum.reject(&(&1 == full_function_name))
    |> Enum.map(fn full_candidate_name ->
      title = "Replace unknown function with '#{full_candidate_name}'"
      range = range(start_line, 0, start_line, String.length(source_line))
      new_text = String.replace(source_line, full_function_name, full_candidate_name)

      create_quickfix(title, uri, range, new_text)
    end)
  end

  defp parse_candidates_string(str) do
    pattern = ~r"[ ]*\* (?<function_name>.*)/.*"

    str
    |> String.split("\n")
    |> Enum.map(&Regex.run(pattern, &1, capture: :all_names))
    |> Enum.reject(&is_nil/1)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp replace_unknown_local_function(uri, %{"message" => message, "range" => range}, source_file) do
    [_, function_name, _function_arity] = Regex.run(@unknown_local_function, message)

    active_module = active_module(source_file, range)

    start_line = start_line_from_range(range)

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

      create_quickfix(title, uri, range, new_text)
    end)
  end

  defp active_module(source_file, range) do
    start_line = start_line_from_range(range)
    metadata = Parser.parse_string(source_file.text, true, true, 1)

    %State.Env{module: active_module} = get_env_from_line(metadata, start_line + 1)

    active_module
  end

  @default_env State.default_env()

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

  defp start_line_from_range(%{"start" => %{"line" => start_line}}), do: start_line

  defp create_quickfix(title, uri, range, new_text) do
    %{
      "title" => title,
      "kind" => "quickfix",
      "edit" => %{
        "changes" => %{
          uri => [
            %{
              "range" => range,
              "newText" => new_text
            }
          ]
        }
      }
    }
  end
end
