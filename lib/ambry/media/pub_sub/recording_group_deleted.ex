defmodule Ambry.Media.PubSub.RecordingGroupDeleted do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Media.RecordingGroup

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%RecordingGroup{} = group), do: new(group.id)
  def new(id) when is_integer(id), do: %__MODULE__{id: id, broadcast_topics: [wildcard_topic()]}

  def wildcard_topic, do: "recording-group-deleted:*"
end
