defmodule AmbryWeb.Player.Tracker do
  @moduledoc """
  TODO: docs
  """

  alias AmbryWeb.Presence

  @topic "ambry:player_sessions"

  def track!(%{id: id} = player) when is_binary(id) do
    {:ok, _ref} =
      Presence.track(
        self(),
        @topic,
        id,
        %{
          online_at: inspect(System.system_time(:second)),
          player: player
        }
      )
  end

  def update!(%{id: id} = player) when is_binary(id) do
    {:ok, _ref} =
      Presence.update(
        self(),
        @topic,
        id,
        &%{&1 | player: player}
      )
  end

  def list do
    Presence.list(@topic)
  end

  def fetch(id) when is_binary(id) do
    case Presence.get_by_key(@topic, id) do
      [] -> :error
      %{metas: [%{player: player}]} -> {:ok, player}
    end
  end
end
