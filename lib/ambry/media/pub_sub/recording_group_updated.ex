defmodule Ambry.Media.PubSub.RecordingGroupUpdated do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Media.RecordingGroup

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%RecordingGroup{} = group) do
    %__MODULE__{id: group.id, broadcast_topics: [wildcard_topic()]}
  end

  def wildcard_topic, do: "recording-group-updated:*"
end
