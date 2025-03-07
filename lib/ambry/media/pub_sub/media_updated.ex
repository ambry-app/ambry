defmodule Ambry.Media.PubSub.MediaUpdated do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Media.Media

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%Media{} = media) do
    %__MODULE__{
      id: media.id,
      broadcast_topics: [media_topic(media), wildcard_topic()]
    }
  end

  def wildcard_topic, do: "media-deleted:*"

  def media_topic(%Media{} = media), do: "media-deleted:#{media.id}"
end
