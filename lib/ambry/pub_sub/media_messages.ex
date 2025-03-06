defmodule Ambry.PubSub.MediaCreated do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Media.Media

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Media{} = media) do
    %__MODULE__{id: media.id, broadcast_topics: ["media-created:*"]}
  end

  @impl true
  def subscribe_topic, do: "media-created:*"
end

defmodule Ambry.PubSub.MediaUpdated do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Media.Media

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Media{} = media) do
    %__MODULE__{
      id: media.id,
      broadcast_topics: ["media-updated:#{media.id}", "media-updated:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "media-updated:*"
end

defmodule Ambry.PubSub.MediaDeleted do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Media.Media

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Media{} = media) do
    %__MODULE__{
      id: media.id,
      broadcast_topics: ["media-deleted:#{media.id}", "media-deleted:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "media-deleted:*"
end

defmodule Ambry.PubSub.BookmarkCreated do
  @moduledoc false
  use Ambry.PubSub.MessageNew

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

defmodule Ambry.PubSub.BookmarkUpdated do
  @moduledoc false
  use Ambry.PubSub.MessageNew

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

defmodule Ambry.PubSub.BookmarkDeleted do
  @moduledoc false
  use Ambry.PubSub.MessageNew

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

defmodule Ambry.PubSub.PlayerStateUpdated do
  @moduledoc false
  use Ambry.PubSub.MessageNew

  alias Ambry.Media.PlayerState

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%PlayerState{} = player_state) do
    %__MODULE__{
      id: player_state.id,
      broadcast_topics: [
        "player-state-updated:#{player_state.id}",
        "player-state-updated:#{player_state.user_id}:#{player_state.media_id}",
        "player-state-updated:*"
      ]
    }
  end

  @impl true
  def subscribe_topic, do: "player-state-updated:*"
end
