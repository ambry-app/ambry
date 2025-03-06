defmodule Ambry.Media.PubSub.MediaCreated do
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
