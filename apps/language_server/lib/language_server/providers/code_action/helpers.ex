defmodule ElixirLS.LanguageServer.Providers.CodeAction.Helpers do
  def start_line_from_range(%{"start" => %{"line" => start_line}}), do: start_line

  def create_quickfix(title, uri, range, new_text) do
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
