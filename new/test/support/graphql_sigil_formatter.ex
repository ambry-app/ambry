defmodule Ambry.GraphQLSigilFormatter do
  @moduledoc """
  Formats GraphQL queries inside sigils.
  """

  @behaviour Mix.Tasks.Format

  @impl Mix.Tasks.Format
  def features(_opts) do
    [sigils: [:G], extensions: []]
  end

  # Absinthe specs are wonky
  @dialyzer {:nowarn_function, format: 2}

  @impl Mix.Tasks.Format
  def format(contents, _opts \\ []) do
    Absinthe.Formatter.format(contents)
  end
end
