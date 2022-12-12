defmodule ElixirLS.LanguageServer.Providers.CodeAction do
  use ElixirLS.LanguageServer.Protocol

  alias ElixirLS.LanguageServer.Providers.CodeAction.{PrefixWithUnderscore, ReplaceRemoteFunction, ReplaceLocalFunction}

  def code_actions(uri, diagnostics, source_file) do
    actions =
      diagnostics
      |> Enum.map(fn diagnostic -> actions(uri, diagnostic, source_file) end)
      |> List.flatten()

    {:ok, actions}
  end

  defp actions(uri, %{"message" => message} = diagnostic, source_file) do
    [
      {PrefixWithUnderscore.pattern(), &PrefixWithUnderscore.get_actions/3},
      {ReplaceRemoteFunction.pattern(), &ReplaceRemoteFunction.get_actions/3},
      {ReplaceLocalFunction.pattern(), &ReplaceLocalFunction.get_actions/3}
    ]
    |> Enum.filter(fn {r, _fun} -> String.match?(message, r) end)
    |> Enum.map(fn {_r, fun} -> fun.(uri, diagnostic, source_file) end)
  end
end
