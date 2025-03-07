defmodule Ambry.Media.PubSub.PlayerStateUpdated do
  @moduledoc false
  use Ambry.PubSub.Message

  alias Ambry.Media.PlayerState

  embedded_schema do
    field :id, :integer
    field :broadcast_topics, {:array, :string}
  end

  def new(%PlayerState{} = player_state) do
    %__MODULE__{
      id: player_state.id,
      broadcast_topics: [player_state_topic(player_state), wildcard_topic()]
    }
  end

  def wildcard_topic, do: "player-state-updated:*"

  def player_state_topic(%PlayerState{} = player_state),
    do: "player-state-updated:#{player_state.id}"
end
