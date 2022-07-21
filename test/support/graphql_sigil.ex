defmodule Ambry.GraphQLSigil do
  @moduledoc """
  Adds the ~G sigil for GraphQL queries.
  """
  def sigil_G(string, []), do: string
end
