defmodule Ambry.Media.PubSub.BookmarkUpdated do
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
        "bookmark-updated:#{bookmark.id}",
        "bookmark-updated:#{bookmark.user_id}:#{bookmark.media_id}",
        "bookmark-updated:*"
      ]
    }
  end

  @impl true
  def subscribe_topic, do: "bookmark-updated:*"
end
