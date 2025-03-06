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
      broadcast_topics: [
        "bookmark-deleted:#{bookmark.id}",
        "bookmark-deleted:#{bookmark.user_id}:#{bookmark.media_id}",
        "bookmark-deleted:*"
      ]
    }
  end

  @impl true
  def subscribe_topic, do: "bookmark-deleted:*"
end
