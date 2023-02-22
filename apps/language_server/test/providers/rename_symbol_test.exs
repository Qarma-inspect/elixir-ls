defmodule ElixirLS.LanguageServer.Providers.RenameSymbolTest do
  use ExUnit.Case, async: true

  import ElixirLS.LanguageServer.Protocol, only: [range: 4]

  alias ElixirLS.LanguageServer.Build
  alias ElixirLS.LanguageServer.Providers.RenameSymbol
  alias ElixirLS.LanguageServer.SourceFile
  alias ElixirLS.LanguageServer.Test.FixtureHelpers
  alias ElixirLS.LanguageServer.Tracer

  @uri "file:///some_file.ex"

  setup_all do
    File.rm_rf!(FixtureHelpers.get_path(".elixir_ls/calls.dets"))

    {:ok, pid} = Tracer.start_link([])
    Tracer.set_project_dir(FixtureHelpers.get_path(""))

    Build.set_compiler_options(ignore_module_conflict: true)

    on_exit(fn ->
      Process.monitor(pid)
      Process.unlink(pid)
      GenServer.stop(pid)

      receive do
        {:DOWN, _, _, _, _} -> :ok
      end
    end)

    Code.compile_file(FixtureHelpers.get_path("rename_example_a.ex"))
    Code.compile_file(FixtureHelpers.get_path("rename_example_b.ex"))
    Code.compile_file(FixtureHelpers.get_path("rename_example_c.ex"))

    :ok
  end

  describe "prepare/3" do
    test "attempt to rename a function from its definition" do
      text = """
      defmodule MyModule do
        def foo(a, b) do
          a + b
        end
      end
      """

      line_number = 1
      columns = Enum.to_list(6..9)
      placeholder = "foo"

      start_column = 6
      end_column = 9

      test_prepare(line_number, columns, text, placeholder, start_column, end_column)
    end

    test "attempt to rename a function from its local call" do
      text = """
      defmodule MyModule do
        def foo(a, b) do
          a + b
        end

        def bar(a) do
          foo(a, a)
        end
      end
      """

      line_number = 6
      columns = Enum.to_list(4..7)
      placeholder = "foo"

      start_column = 4
      end_column = 7

      test_prepare(line_number, columns, text, placeholder, start_column, end_column)
    end

    test "attempt to rename a function from its remote call" do
      text = """
      defmodule MyModule do
        def foo(a, b) do
          a + b
        end
      end

      defmodule MySecondModule do
        def bar(a) do
          MyModule.foo(a, a)
        end
      end
      """

      line_number = 8
      columns = Enum.to_list(13..16)
      placeholder = "foo"

      start_column = 4
      end_column = 16

      test_prepare(line_number, columns, text, placeholder, start_column, end_column)
    end

    test "attempt to rename a function being an argument" do
      text = """
      defmodule MyModule do
        def foo(x) do
          x + 1
        end

        def bar(l) do
          Enum.map(l, &foo/1)
        end
      end
      """

      line_number = 6
      columns = Enum.to_list(17..20)
      placeholder = "foo"

      start_column = 17
      end_column = 20

      test_prepare(line_number, columns, text, placeholder, start_column, end_column)
    end

    test "attempt to rename a variable" do
      text = """
      defmodule MyModule do
        def foo([x | xs]) do
          x
        end
      end
      """

      line_number = 1
      columns = Enum.to_list(11..12)
      placeholder = "x"

      start_column = 11
      end_column = 12

      test_prepare(line_number, columns, text, placeholder, start_column, end_column)
    end

    test "attempt to rename a string" do
      text = """
      defmodule MyModule do
        def foo(x) do
          x + 1
        end

        def bar(l) do
          "foo"
        end
      end
      """

      line_number = 6
      columns = Enum.to_list(17..20)

      source_file = %SourceFile{text: text, version: 0}

      Enum.each(columns, fn column ->
        position = %{"character" => column, "line" => line_number}

        assert {:ok, nil} = RenameSymbol.prepare(@uri, position, source_file)
      end)
    end

    defp test_prepare(line_number, columns, text, placeholder, start_column, end_column) do
      source_file = %SourceFile{text: text, version: 0}

      Enum.each(columns, fn column ->
        position = %{"character" => column, "line" => line_number}

        expected_result = %{
          range: range(line_number, start_column, line_number, end_column),
          placeholder: placeholder
        }

        assert {:ok, ^expected_result} = RenameSymbol.prepare(@uri, position, source_file)
      end)
    end
  end

  describe "rename/4" do
    setup do
      file_path_a = FixtureHelpers.get_path("rename_example_a.ex")
      file_path_b = FixtureHelpers.get_path("rename_example_b.ex")
      file_path_c = FixtureHelpers.get_path("rename_example_c.ex")

      text_a = File.read!(file_path_a)
      text_b = File.read!(file_path_b)
      text_c = File.read!(file_path_c)

      source_file_a = %SourceFile{text: text_a, version: 0}
      source_file_b = %SourceFile{text: text_b, version: 0}
      source_file_c = %SourceFile{text: text_c, version: 0}

      uri_a = SourceFile.Path.to_uri(file_path_a)
      uri_b = SourceFile.Path.to_uri(file_path_b)
      uri_c = SourceFile.Path.to_uri(file_path_c)

      {:ok,
       %{source_file_a: source_file_a, source_file_b: source_file_b, source_file_c: source_file_c, uri_a: uri_a, uri_b: uri_b, uri_c: uri_c}}
    end

    test "rename a function from its definition", %{
      source_file_a: source_file_a,
      uri_a: uri_a,
      uri_b: uri_b
    } do
      line_number = 1
      columns = Enum.to_list(6..9)

      test_rename_function(source_file_a, uri_a, uri_a, uri_b, line_number, columns)
    end

    test "rename a function from its local call", %{
      source_file_a: source_file_a,
      uri_a: uri_a,
      uri_b: uri_b
    } do
      line_number = 11
      columns = Enum.to_list(8..11)

      test_rename_function(source_file_a, uri_a, uri_a, uri_b, line_number, columns)
    end

    test "rename a function from its remote call", %{
      source_file_b: source_file_b,
      uri_a: uri_a,
      uri_b: uri_b
    } do
      line_number = 4
      columns = Enum.to_list(33..36)

      test_rename_function(source_file_b, uri_b, uri_a, uri_b, line_number, columns)
    end

    test "rename a function being an argument", %{
      source_file_a: source_file_a,
      uri_a: uri_a,
      uri_b: uri_b
    } do
      line_number = 8
      columns = Enum.to_list(19..22)

      test_rename_function(source_file_a, uri_a, uri_a, uri_b, line_number, columns)
    end

    test "rename a variable from a function header", %{source_file_a: source_file, uri_a: uri} do
      new_name = "head"

      ranges = [range(5, 11, 5, 12), range(11, 12, 11, 13)]

      expected_result = %{
        "changes" => %{
          uri =>
            Enum.map(ranges, fn range ->
              %{
                "range" => range,
                "newText" => new_name
              }
            end)
        }
      }

      line_number = 5
      columns = Enum.to_list(11..12)

      Enum.each(columns, fn column ->
        position = %{"character" => column, "line" => line_number}

        assert {:ok, ^expected_result} =
                 RenameSymbol.rename(uri, position, new_name, source_file)
      end)
    end

    test "rename a variable defined in a function header", %{source_file_c: source_file, uri_c: uri} do
      new_name = "z"

      # `x` defined in the function header
      ranges_list = [
        {5, 17, 5, 18},
        {6, 18, 6, 19}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)

      # `y` defined in the first function header
      ranges_list = [
        {1, 16, 1, 17},
        {2, 4, 2, 5}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)

      # `y` defined in the second function header
      ranges_list = [
        {5, 21, 5, 22},
        {6, 21, 6, 22}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)
    end

    test "rename a variable used in a guard", %{source_file_c: source_file, uri_c: uri} do
      new_name = "z"

      # `h` defined in the function header
      ranges_list = [
        {5, 13, 5, 14},
        {5, 37, 5, 38},
        {6, 8, 6, 9},
        {9, 11, 9, 12},
        {12, 16, 12, 17}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)

      # `x` defined in the case clause
      ranges_list = [
        {10, 8, 10, 9},
        {10, 15, 10, 16},
        {11, 13, 11, 14}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)

      # `x` defined in the anonymous function
      ranges_list = [
        {17, 29, 17, 30},
        {17, 36, 17, 37},
        {17, 44, 17, 45},
        {17, 53, 17, 54}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)
    end

    test "rename a redefined variable", %{source_file_c: source_file, uri_c: uri} do
      new_name = "z"

      # `x` redefined right below the function header
      ranges_list = [
        {6, 4, 6, 5},
        {17, 17, 17, 18}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)

      # `x` redefined inside `if` clause
      ranges_list = [
        {12, 12, 12, 13},
        {13, 12, 13, 13}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)

      # redefined `h`
      ranges_list = [
        {8, 4, 8, 5},
        {17, 57, 17, 58}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)

      # `x` with assigned result of the `Enum.map/2` function
      ranges_list = [
        {17, 4, 17, 5},
        {18, 4, 18, 5}
      ]

      test_rename_variable(source_file, uri, ranges_list, new_name)
    end

    defp test_rename_function(source_file, uri, uri_a, uri_b, line_number, columns) do
      new_name = "bar"

      uri_a_ranges = [range(8, 19, 8, 22), range(11, 8, 11, 11), range(1, 6, 1, 9)]
      uri_b_ranges = [range(4, 33, 4, 36), range(4, 57, 4, 60)]

      expected_result = %{
        "changes" => %{
          uri_a =>
            Enum.map(uri_a_ranges, fn range ->
              %{
                "range" => range,
                "newText" => new_name
              }
            end),
          uri_b =>
            Enum.map(uri_b_ranges, fn range ->
              %{
                "range" => range,
                "newText" => new_name
              }
            end)
        }
      }

      Enum.each(columns, fn column ->
        position = %{"character" => column, "line" => line_number}

        assert {:ok, ^expected_result} = RenameSymbol.rename(uri, position, new_name, source_file)
      end)
    end

    defp test_rename_variable(source_file, uri, ranges_list, new_name) do
      expected_result = %{
        "changes" => %{
          uri =>
            Enum.map(ranges_list, fn {start_line, start_column, end_line, end_column} ->
              %{
                "range" => range(start_line, start_column, end_line, end_column),
                "newText" => new_name
              }
            end)
        }
      }

      Enum.each(ranges_list, fn {line, start_column, line, end_column} ->
        Enum.each(start_column..end_column, fn column ->
          position = %{"character" => column, "line" => line}

          assert {:ok, ^expected_result} =
                   RenameSymbol.rename(uri, position, new_name, source_file)
        end)
      end)
    end
  end
end
