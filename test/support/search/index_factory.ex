defmodule Ambry.Search.IndexFactory do
  @moduledoc false

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.People.Person
  alias Ambry.Search.Index

  def insert_index!(%Book{id: id}), do: Index.insert!(:book, id)
  def insert_index!(%Person{id: id}), do: Index.insert!(:person, id)
  def insert_index!(%Series{id: id}), do: Index.insert!(:series, id)
end
