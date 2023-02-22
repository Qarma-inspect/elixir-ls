defmodule ElixirLS.Test.RenameExampleB do
  alias ElixirLS.Test.RenameExampleA

  def foo(x) do
    ElixirLS.Test.RenameExampleA.foo(x) + RenameExampleA.foo(x)
  end
end
