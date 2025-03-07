defmodule Ambry.Books.PubSub.BookUpdated do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Books.Book

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Book{} = book) do
    %__MODULE__{
      id: book.id,
      broadcast_topics: [book_topic(book), wildcard_topic()]
    }
  end

  def wildcard_topic, do: "book-updated:*"

  def book_topic(%Book{} = book), do: "book-updated:#{book.id}"
end
