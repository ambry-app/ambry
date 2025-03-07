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
      broadcast_topics: [wildcard_topic()]
    }
  end

  def wildcard_topic, do: "bookmark-created:*"
end
