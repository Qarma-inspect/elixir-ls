defmodule ElixirLS.LanguageServer.Providers.CodeActionTest do
  use ExUnit.Case

  alias ElixirLS.LanguageServer.Providers.CodeAction
  alias ElixirLS.LanguageServer.SourceFile

  @uri "file:///some_file.ex"

  describe "prefix with underscore" do
    test "variable in the function header" do
      text = """
      defmodule Example do
        def foo(var) do
          42
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(1, 2, 1, 17)

      diagnostic =
        "var"
        |> create_message_for_unused_variable()
        |> create_diagnostic(diagnostic_range)

      assert {:ok, [underscore_action]} = CodeAction.code_actions(@uri, diagnostic, source_file)

      new_text = "  def foo(_var) do"
      quickfix_range = create_range(1, 0, 1, 17)

      assert_quickfix(new_text, quickfix_range, underscore_action)
    end

    test "assignment" do
      text = """
      defmodule Example do
        def foo do
          var = 42
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(2, 4, 2, 12)

      diagnostic =
        "var"
        |> create_message_for_unused_variable()
        |> create_diagnostic(diagnostic_range)

      assert {:ok, [underscore_action]} = CodeAction.code_actions(@uri, diagnostic, source_file)

      new_text = "    _var = 42"
      quickfix_range = create_range(2, 0, 2, 12)

      assert_quickfix(new_text, quickfix_range, underscore_action)
    end

    test "pattern matching on map" do
      text = """
      defmodule Example do
        def foo do
          %{a: var} = %{a: 42}
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(2, 4, 2, 24)

      diagnostic =
        "var"
        |> create_message_for_unused_variable()
        |> create_diagnostic(diagnostic_range)

      assert {:ok, [underscore_action]} = CodeAction.code_actions(@uri, diagnostic, source_file)

      new_text = "    %{a: _var} = %{a: 42}"
      quickfix_range = create_range(2, 0, 2, 24)

      assert_quickfix(new_text, quickfix_range, underscore_action)
    end

    test "pattern matching on list" do
      text = """
      defmodule Example do
        def foo do
          [var] = [42]
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(2, 4, 2, 16)

      diagnostic =
        "var"
        |> create_message_for_unused_variable()
        |> create_diagnostic(diagnostic_range)

      assert {:ok, [underscore_action]} = CodeAction.code_actions(@uri, diagnostic, source_file)

      new_text = "    [_var] = [42]"
      quickfix_range = create_range(2, 0, 2, 16)

      assert_quickfix(new_text, quickfix_range, underscore_action)
    end

    test "argument of an anonymous function" do
      text = """
      defmodule Example do
        def foo do
          Enum.map([42], fn var -> 42 end)
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(2, 4, 2, 36)

      diagnostic =
        "var"
        |> create_message_for_unused_variable()
        |> create_diagnostic(diagnostic_range)

      assert {:ok, [underscore_action]} = CodeAction.code_actions(@uri, diagnostic, source_file)

      new_text = "    Enum.map([42], fn _var -> 42 end)"
      quickfix_range = create_range(2, 0, 2, 36)

      assert_quickfix(new_text, quickfix_range, underscore_action)
    end

    test "no quickfix if there are two variables of the same name" do
      text = """
      defmodule Example do
        def foo do
          var = Enum.map([42], fn var -> 42 end)
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(2, 4, 2, 42)

      diagnostic =
        "var"
        |> create_message_for_unused_variable()
        |> create_diagnostic(diagnostic_range)

      assert {:ok, []} = CodeAction.code_actions(@uri, diagnostic, source_file)
    end

    test "functions are not matched for quickfix" do
      text = """
      defmodule Example do
        def foo do
          count = Enum.count([40, 2])
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(2, 4, 2, 31)

      diagnostic =
        "count"
        |> create_message_for_unused_variable()
        |> create_diagnostic(diagnostic_range)

      assert {:ok, [underscore_action]} = CodeAction.code_actions(@uri, diagnostic, source_file)

      new_text = "    _count = Enum.count([40, 2])"
      quickfix_range = create_range(2, 0, 2, 31)

      assert_quickfix(new_text, quickfix_range, underscore_action)
    end

    defp create_message_for_unused_variable(variable) do
      "variable \"#{variable}\" is unused (if the variable is not meant to be used, prefix it with an underscore)"
    end
  end

  describe "replace unknown function" do
    test "functions in Enum" do
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

      diagnostic_range = create_range(2, 10, 2, 21)

      diagnostic = create_diagnostic(message, diagnostic_range)

      assert {:ok, [replace_with_concat, replace_with_count]} =
               CodeAction.code_actions(@uri, diagnostic, source_file)

      new_text = "    var = Enum.concat([2, 3])"
      quickfix_range = create_range(2, 0, 2, 29)

      assert_quickfix(new_text, quickfix_range, replace_with_concat)

      new_text = "    var = Enum.count([2, 3])"
      quickfix_range = create_range(2, 0, 2, 29)

      assert_quickfix(new_text, quickfix_range, replace_with_count)
    end
  end

  describe "replace unknown local function" do
    test "function call" do
      text = """
      defmodule Example do
        def main do
          fo()
        end

        def foo do
          42
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(2, 4, 2, 8)

      diagnostic =
        "fo"
        |> create_message_for_unknown_function()
        |> create_diagnostic(diagnostic_range, 1)

      assert {:ok, [action]} = CodeAction.code_actions(@uri, diagnostic, source_file)

      new_text = "    foo()"
      quickfix_range = create_range(2, 0, 2, 8)

      assert_quickfix(new_text, quickfix_range, action)
    end

    test "function as an argument" do
      text = """
      defmodule Example do
        def main do
          Enum.map([4, 2], &fo/1)
        end

        def foo(var) do
          var
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(2, 4, 2, 27)

      diagnostic =
        "fo"
        |> create_message_for_unknown_function()
        |> create_diagnostic(diagnostic_range, 1)

      assert {:ok, [action]} = CodeAction.code_actions(@uri, diagnostic, source_file)

      new_text = "    Enum.map([4, 2], &foo/1)"
      quickfix_range = create_range(2, 0, 2, 27)

      assert_quickfix(new_text, quickfix_range, action)
    end

    test "function from a different module should not be proposed" do
      text = """
      defmodule Example do
        defmodule Inner do
          def foo(var) do
            var
          end
        end

        def main do
          Enum.map([4, 2], &fo/1)
        end
      end
      """

      source_file = %SourceFile{text: text}

      diagnostic_range = create_range(8, 4, 8, 27)

      diagnostic =
        "fo"
        |> create_message_for_unknown_function()
        |> create_diagnostic(diagnostic_range, 1)

      assert {:ok, []} = CodeAction.code_actions(@uri, diagnostic, source_file)
    end

    defp create_message_for_unknown_function(function_name) do
      "(CompileError) undefined function #{function_name}/0 (expected Example to define such a function or for it to be imported, but none are available)"
    end
  end

  defp create_range(start_line, start_character, end_line, end_character) do
    %{
      "end" => %{"character" => end_character, "line" => end_line},
      "start" => %{"character" => start_character, "line" => start_line}
    }
  end

  defp create_diagnostic(message, range, severity \\ 2) do
    [
      %{
        "message" => message,
        "range" => range,
        "severity" => severity,
        "source" => "Elixir"
      }
    ]
  end

  defp assert_quickfix(new_text, range, action) do
    assert %{
             "edit" => %{
               "changes" => %{
                 @uri => [
                   %{
                     "newText" => ^new_text,
                     "range" => ^range
                   }
                 ]
               }
             }
           } = action
  end
end
