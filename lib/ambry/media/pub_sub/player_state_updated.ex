defmodule Ambry.Media.PubSub.PlayerStateUpdated do
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
