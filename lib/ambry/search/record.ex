defmodule Ambry.Search.Record do
  @moduledoc """
  One row of the search index: a book, a person or a series, reduced to three
  weighted text columns and the `tsvector` a trigger builds from them.

  `Ambry.Search.Index` decides what goes in the columns; nothing else writes
  here.
  """
  use Ecto.Schema

  alias Ambry.Search.Reference

  @primary_key {:reference, Reference.Type, []}

  schema "search_index" do
    field :primary, :string
    field :secondary, :string
    field :tertiary, :string
  end
end
