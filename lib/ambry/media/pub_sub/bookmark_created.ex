defmodule Ambry.Media.PubSub.BookmarkCreated do
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
        "bookmark-created:#{bookmark.user_id}:#{bookmark.media_id}",
        "bookmark-created:*"
      ]
    }
  end

  @impl true
  def subscribe_topic, do: "bookmark-created:*"
end
