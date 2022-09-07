defmodule Ambry.Search.Record do
  @moduledoc """
  Represents a record in the search index, which is either a media, author, narrator or series.
  """
  use Ecto.Schema

  alias Ambry.Ecto.Types.Reference

  @primary_key {:reference, Reference, []}

  schema "search_index" do
    field :dependencies, {:array, Reference}
    field :primary, :string
    field :secondary, :string
    field :tertiary, :string
  end
end
