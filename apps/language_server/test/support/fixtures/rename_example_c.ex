defmodule ElixirLS.Test.RenameExampleC do
  def count([], y) do
    y
  end

  def count([h | x], y) when is_atom(h) do
    x = h + count(x, y)

    h =
      case h do
        x when x == 3 ->
          if x > 3 do
            x = h
            x
          end
      end

    x = Enum.map(x, fn %{x1: x, x2: x} when x > 3 -> x + h end)
    x
  end
end
