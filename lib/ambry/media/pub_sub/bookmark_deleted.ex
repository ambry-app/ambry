defmodule Ambry.Media.PubSub.BookmarkDeleted do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Media.Bookmark

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Bookmark{} = bookmark) do
    %__MODULE__{
      id: bookmark.id,
      broadcast_topics: [bookmark_topic(bookmark), wildcard_topic()]
    }
  end

  def wildcard_topic, do: "bookmark-deleted:*"

  def bookmark_topic(%Bookmark{} = bookmark), do: "bookmark-deleted:#{bookmark.id}"
end
