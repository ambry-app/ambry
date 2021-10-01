defmodule Ambry.Media.PlayerState do
  @moduledoc """
  A user's progress and settings for a specific media.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ambry.Accounts.User
  alias Ambry.Media.Media

  schema "player_states" do
    belongs_to :media, Media
    belongs_to :user, User

    field :playback_rate, :decimal, default: 1
    field :position, :decimal, default: 0
    field :duration, :decimal

    timestamps()
  end

  @doc false
  def changeset(player_state, attrs) do
    player_state
    |> cast(attrs, [:position, :duration, :playback_rate, :media_id, :user_id])
    |> validate_required([:position, :playback_rate, :media_id, :user_id])
  end
end
