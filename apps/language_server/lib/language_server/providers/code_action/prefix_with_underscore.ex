defmodule ElixirLS.LanguageServer.Providers.CodeAction.PrefixWithUnderscore do
  @behaviour ElixirLS.LanguageServer.Providers.CodeAction

  use ElixirLS.LanguageServer.Protocol

  alias ElixirLS.LanguageServer.Providers.CodeAction.Helpers
  alias ElixirLS.LanguageServer.SourceFile

  @impl true
  def pattern, do: ~r/variable "(.*)" is unused/

  @impl true
  def get_actions(uri, %{"message" => message, "range" => range}, source_file) do
    [_, variable] = Regex.run(pattern(), message)

    start_line = Helpers.start_line_from_range(range)

    source_line =
      source_file
      |> SourceFile.lines()
      |> Enum.at(start_line)

    pattern = Regex.compile!("(?<![[:alnum:]._])#{Regex.escape(variable)}(?![[:alnum:]._])")

    if pattern |> Regex.scan(source_line) |> length() == 1 do
      title = "Add '_' to unused '#{variable}' variable"
      range = range(start_line, 0, start_line, String.length(source_line))
      new_text = String.replace(source_line, pattern, "_" <> variable)

      Helpers.create_quickfix(title, uri, range, new_text)
    else
      []
    end
  end
end
