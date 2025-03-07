defmodule AmbryWeb.Player.PubSub.PlayerUpdated do
  @moduledoc false
  use Ambry.PubSub.Message

  alias AmbryWeb.Player

  embedded_schema do
    field :id, :string
    field :broadcast_topics, {:array, :string}
  end

  def new(%Player{id: player_id} = player) when is_binary(player_id) do
    %__MODULE__{
      id: player_id,
      broadcast_topics: [player_topic(player)]
    }
  end

  def player_topic(%Player{id: player_id}) when is_binary(player_id), do: "player:#{player_id}"
end
