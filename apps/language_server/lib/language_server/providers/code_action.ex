defmodule ElixirLS.LanguageServer.Providers.CodeAction do
  use ElixirLS.LanguageServer.Protocol

  alias ElixirLS.LanguageServer.SourceFile

  @variable_is_unused ~r/variable "(.*)" is unused/
  @unknown_remote_function_pattern ~r/(.*)\/(.*) is undefined or private. .*:\n(.*)/s

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
      {@unknown_remote_function_pattern, &replace_unknown_function/3}
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
      %{
        "title" => "Add '_' to unused variable",
        "kind" => "quickfix",
        "edit" => %{
          "changes" => %{
            uri => [
              %{
                "newText" => String.replace(source_line, pattern, "_" <> variable),
                "range" => range(start_line, 0, start_line, String.length(source_line))
              }
            ]
          }
        }
      }
    else
      []
    end
  end

  defp replace_unknown_function(uri, %{"message" => message, "range" => range}, source_file) do
    [_, full_function_name, _function_arity, candidates_string] =
      Regex.run(@unknown_remote_function_pattern, message)

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
      %{
        "title" => "Replace unknown function with '#{full_candidate_name}'",
        "kind" => "quickfix",
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
                "newText" => String.replace(source_line, full_function_name, full_candidate_name)
              }
            ]
          }
        }
      }
    end)
  end

  defp start_line_from_range(%{"start" => %{"line" => start_line}}), do: start_line

  defp parse_candidates_string(str) do
    pattern = ~r"[ ]*\* (?<function_name>.*)/.*"

    str
    |> String.split("\n")
    |> Enum.map(&Regex.run(pattern, &1, capture: :all_names))
    |> Enum.reject(&is_nil/1)
    |> List.flatten()
    |> Enum.uniq()
  end
end
