defmodule ElixirLS.Test.RenameExampleA do
  def foo(h) do
    h + 1
  end

  def fun([h | t]) do
    x =
      t
      |> Enum.map(&foo/1)
      |> Enum.count()

    x + foo(h)
  end
end
