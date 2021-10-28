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

    field :playback_rate, :decimal, default: Decimal.new(1)
    field :position, :decimal, default: Decimal.new(0)

    field :status, Ecto.Enum,
      values: [:not_started, :in_progress, :finished],
      default: :not_started

    timestamps()
  end

  @doc false
  def changeset(player_state, attrs) do
    player_state
    |> cast(attrs, [:position, :playback_rate, :media_id, :user_id])
    |> validate_required([:position, :playback_rate, :media_id, :user_id])
    |> compute_and_put_status()
  end

  defp compute_and_put_status(changeset) do
    case changeset do
      %{data: %{media: %{duration: duration}}} ->
        position = get_field(changeset, :position)

        cond do
          # 10 seconds until it counts as started
          Decimal.lt?(position, 10) ->
            put_change(changeset, :status, :not_started)

          # 10 seconds from end it counts as finished
          duration |> Decimal.sub(position) |> Decimal.lt?(10) ->
            put_change(changeset, :status, :finished)

          # otherwise it's in progress
          true ->
            put_change(changeset, :status, :in_progress)
        end

      changeset ->
        changeset
    end
  end
end
