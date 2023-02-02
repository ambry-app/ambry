defmodule AmbryWeb.Player.Tracker do
  @moduledoc """
  TODO: docs
  """

  alias AmbryWeb.Presence

  @topic "ambry:player_sessions"

  def track!(%{id: id} = player, user) do
    {:ok, _ref} =
      Presence.track(
        self(),
        @topic,
        id,
        %{
          online_at: inspect(System.system_time(:second)),
          user: user,
          player: player
        }
      )
  end

  def update!(%{id: id} = player) do
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

  def get(id) do
    case Presence.get_by_key(@topic, id) do
      [] -> nil
      %{metas: [%{player: player}]} -> player
    end
  end
end
