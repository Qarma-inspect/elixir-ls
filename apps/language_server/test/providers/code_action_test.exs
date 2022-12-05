defmodule ElixirLS.LanguageServer.Providers.CodeActionTest do
  use ExUnit.Case

  alias ElixirLS.LanguageServer.Providers.CodeAction
  alias ElixirLS.LanguageServer.SourceFile

  test "replace unknown function" do
    uri = "file:///some_file.ex"

    text = """
    defmodule Example do
      def foo do
        var = Enum.counts([2, 3])
      end
    end
    """

    source_file = %SourceFile{text: text}

    message = "Enum.counts/1 is undefined or private. Did you mean:

    * concat/1
    * concat/2
    * count/1
    * count/2
    "

    diagnostic = [
      %{
        "message" => message,
        "range" => %{
          "end" => %{"character" => 21, "line" => 2},
          "start" => %{"character" => 10, "line" => 2}
        },
        "severity" => 2,
        "source" => "Elixir"
      }
    ]

    assert {:ok, [replace_with_concat, replace_with_count]} =
             CodeAction.code_actions(uri, diagnostic, source_file)

    assert %{
             "edit" => %{
               "changes" => %{
                 ^uri => [
                   %{
                     "newText" => "    var = Enum.concat([2, 3])",
                     "range" => %{
                       "end" => %{"character" => 29, "line" => 2},
                       "start" => %{"character" => 0, "line" => 2}
                     }
                   }
                 ]
               }
             }
           } = replace_with_concat

    assert %{
             "edit" => %{
               "changes" => %{
                 ^uri => [
                   %{
                     "newText" => "    var = Enum.count([2, 3])",
                     "range" => %{
                       "end" => %{"character" => 29, "line" => 2},
                       "start" => %{"character" => 0, "line" => 2}
                     }
                   }
                 ]
               }
             }
           } = replace_with_count
  end
end
