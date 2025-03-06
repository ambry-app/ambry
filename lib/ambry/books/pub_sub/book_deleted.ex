defmodule Ambry.Books.PubSub.BookDeleted do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Books.Book

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Book{} = book) do
    %__MODULE__{
      id: book.id,
      broadcast_topics: ["book-deleted:#{book.id}", "book-deleted:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "book-deleted:*"
end
