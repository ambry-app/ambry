defmodule Ambry.People do
  @moduledoc """
  Functions for dealing with People.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.People.Person
  alias Ambry.Repo

  @doc """
  Gets an people and all of their books (either authored or narrated).

  Books are listed in descending order based on publish date.
  """
  def get_person_with_books!(person_id) do
    books_query = from b in Book, order_by: [desc: b.published]

    Person
    |> preload(
      authors: [books: ^{books_query, [:authors, series_books: :series]}],
      narrators: [books: ^{books_query, [:authors, series_books: :series]}]
    )
    |> Repo.get!(person_id)
  end
end
