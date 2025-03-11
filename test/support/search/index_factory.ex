defmodule Ambry.Search.IndexFactory do
  @moduledoc false

  # TODO: remove me

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Media.Media
  alias Ambry.People.Person
  alias Ambry.Search.Index

  def insert_index!(%Book{id: id}), do: Index.insert!(:book, id)
  def insert_index!(%Person{id: id}), do: Index.insert!(:person, id)
  def insert_index!(%Series{id: id}), do: Index.insert!(:series, id)
  def insert_index!(%Media{id: id}), do: Index.insert!(:media, id)
end
