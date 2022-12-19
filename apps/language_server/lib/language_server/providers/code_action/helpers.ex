defmodule ElixirLS.LanguageServer.Providers.CodeAction.Helpers do
  alias ElixirSense.Core.{Metadata, Parser, State}

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

  @default_env State.default_env()

  def active_module(source_file, range) do
    start_line = start_line_from_range(range)
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
end
