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

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(player_state, attrs) do
    player_state
    |> cast(attrs, [:position, :playback_rate, :media_id, :user_id])
    |> validate_required([:position, :playback_rate, :media_id, :user_id])
    |> validate_playback_rate()
    |> compute_and_put_status()
  end

  defp validate_playback_rate(changeset) do
    validate_change(changeset, :playback_rate, fn :playback_rate, rate ->
      if Decimal.eq?(rate, 0) do
        [playback_rate: "cannot be zero"]
      else
        []
      end
    end)
  end

  defp compute_and_put_status(changeset) do
    duration = get_duration!(changeset)
    position = get_field(changeset, :position)

    cond do
      # 1 minute until it counts as started
      Decimal.lt?(position, 60) ->
        put_change(changeset, :status, :not_started)

      # 2 minutes from end it counts as finished
      duration |> Decimal.sub(position) |> Decimal.lt?(120) ->
        put_change(changeset, :status, :finished)

      # otherwise it's in progress
      true ->
        put_change(changeset, :status, :in_progress)
    end
  end

  defp get_duration!(%Ecto.Changeset{data: %__MODULE__{media: %Media{duration: duration}}}) do
    duration
  end

  defp get_duration!(changeset) do
    media_id = get_field(changeset, :media_id)
    %Media{duration: %Decimal{} = duration} = Ambry.Media.get_media!(media_id)
    duration
  end
end
