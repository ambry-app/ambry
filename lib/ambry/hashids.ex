defmodule Ambry.Hashids do
  @moduledoc """
  Encode and decode simple hashids.
  """

  use Boundary

  @coder Hashids.new([])

  def encode(id) do
    Hashids.encode(@coder, id)
  end

  def decode(data) do
    Hashids.decode(@coder, data)
  end
end
