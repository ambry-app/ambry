defmodule Ambry.Media.PubSub.MediaDeleted do
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
      broadcast_topics: ["media-deleted:#{media.id}", "media-deleted:*"]
    }
  end

  @impl true
  def subscribe_topic, do: "media-deleted:*"
end
