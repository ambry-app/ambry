defmodule Ambry.GraphQLSigilFormatter do
  @moduledoc """
  Formats GraphQL queries inside sigils.
  """

  @behaviour Mix.Tasks.Format

  alias Mix.Tasks.Format

  @impl Format
  def features(_opts) do
    [sigils: [:G], extensions: []]
  end

  # Absinthe specs are wonky
  @dialyzer {:nowarn_function, format: 2}

  @impl Format
  def format(contents, _opts \\ []) do
    Absinthe.Formatter.format(contents)
  end
end
