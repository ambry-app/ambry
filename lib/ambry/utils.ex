defmodule Ambry.Utils do
  @moduledoc """
  Grab-bag of helpful utility functions
  """

  defmacro tap_ok(tuple, fun) do
    quote bind_quoted: [fun: fun, tuple: tuple] do
      case tuple do
        {:ok, value} -> _res = fun.(value)
        _other -> :noop
      end

      tuple
    end
  end
end
