defmodule AmbryWeb.Components.PlayerStateTiles do
  @moduledoc """
  Renders a responsive tiled grid of player states with play buttons.
  """

  use AmbryWeb, :component

  alias AmbryWeb.BookLive.PlayButton
  alias Surface.Components.LiveRedirect

  prop player_states, :list
  prop show_load_more, :boolean, default: false
  prop load_more, :event

  prop user, :any, required: true
  prop browser_id, :string, required: true

  defp progress_percent(%{position: position, media: %{duration: duration}}) do
    position
    |> Decimal.div(duration)
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end
end
