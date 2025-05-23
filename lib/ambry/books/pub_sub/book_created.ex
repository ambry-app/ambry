defmodule Ambry.Books.PubSub.BookCreated do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Books.Book

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Book{} = book) do
    %__MODULE__{id: book.id, broadcast_topics: [wildcard_topic()]}
  end

  def wildcard_topic, do: "book-created:*"
end
