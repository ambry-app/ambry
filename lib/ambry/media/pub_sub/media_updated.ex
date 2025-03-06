defmodule Ambry.Media.PubSub.MediaUpdated do
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
