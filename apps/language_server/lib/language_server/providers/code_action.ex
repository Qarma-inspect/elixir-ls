defmodule ElixirLS.LanguageServer.Providers.CodeAction do
  alias ElixirLS.LanguageServer.Providers.CodeAction.{
    PrefixWithUnderscore,
    ReplaceRemoteFunction,
    ReplaceLocalFunction,
    UnknownModule
  }

  alias ElixirLS.LanguageServer.SourceFile

  @callback pattern() :: Regex.t()
  @callback get_actions(uri :: String.t(), diagnostic :: map(), source_file :: %SourceFile{}) ::
              map()

  def code_actions(uri, diagnostics, source_file) do
    actions =
      diagnostics
      |> Enum.map(fn diagnostic -> actions(uri, diagnostic, source_file) end)
      |> List.flatten()

    {:ok, actions}
  end

  defp actions(uri, %{"message" => message} = diagnostic, source_file) do
    [PrefixWithUnderscore, ReplaceRemoteFunction, ReplaceLocalFunction, UnknownModule]
    |> Enum.filter(fn module -> String.match?(message, module.pattern()) end)
    |> Enum.map(fn module -> module.get_actions(uri, diagnostic, source_file) end)
  end
end
