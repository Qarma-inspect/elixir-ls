defmodule ElixirLS.LanguageServer.Providers.CodeAction.ReplaceRemoteFunction do
  use ElixirLS.LanguageServer.Protocol

  alias ElixirLS.LanguageServer.Providers.CodeAction.Helpers
  alias ElixirLS.LanguageServer.SourceFile
  
  @spec pattern :: Regex.t()
  def pattern, do: ~r/(.*)\/(.*) is undefined or private. .*:\n(.*)/s

  def get_actions(uri, %{"message" => message, "range" => range}, source_file) do
    [_, full_function_name, _function_arity, candidates_string] =
      Regex.run(pattern(), message)

    function_module =
      full_function_name
      |> String.split(".")
      |> Enum.slice(0..-2//1)
      |> Enum.join(".")

    start_line = Helpers.start_line_from_range(range)

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

      Helpers.create_quickfix(title, uri, range, new_text)
    end)
  end

  defp parse_candidates_string(str) do
    parse_pattern = ~r"[ ]*\* (?<function_name>.*)/.*"

    str
    |> String.split("\n")
    |> Enum.map(&Regex.run(parse_pattern, &1, capture: :all_names))
    |> Enum.reject(&is_nil/1)
    |> List.flatten()
    |> Enum.uniq()
  end
end
