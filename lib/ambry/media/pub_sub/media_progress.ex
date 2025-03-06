defmodule Ambry.Media.PubSub.MediaProgress do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Media.Media

  embedded_schema do
    field :id, :integer
    field :progress, :decimal
    field :broadcast_topics, {:array, :string}
  end

  def new(%Media{} = media, progress) do
    %__MODULE__{
      id: media.id,
      progress: progress,
      broadcast_topics: ["media-progress"]
    }
  end

  @impl true
  def subscribe_topic, do: "media-progress"
end
