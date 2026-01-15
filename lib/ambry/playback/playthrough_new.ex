defmodule Ambry.Playback.PlaythroughNew do
  @moduledoc """
  Event-sourced playthrough state.

  This table contains state that is 100% derived from playback events.
  The state can be rebuilt at any time by reducing the event stream.
  """

  use Ecto.Schema

  alias Ambry.Accounts.User
  alias Ambry.Media.Media

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "playthroughs_new" do
    belongs_to :media, Media, type: :id
    belongs_to :user, User, type: :id

    field :status, Ecto.Enum, values: [:in_progress, :finished, :abandoned, :deleted]

    field :started_at, Ambry.Ecto.UtcDateTimeMs
    field :finished_at, Ambry.Ecto.UtcDateTimeMs
    field :abandoned_at, Ambry.Ecto.UtcDateTimeMs
    field :deleted_at, Ambry.Ecto.UtcDateTimeMs

    field :position, :decimal
    field :rate, :decimal

    field :last_event_at, Ambry.Ecto.UtcDateTimeMs

    field :refreshed_at, :utc_datetime_usec
  end

  @doc """
  Reduces a list of events (sorted by timestamp ascending) into playthrough state.

  Returns a map with all the derived fields, suitable for insertion.
  """
  def reduce(events, playthrough_id, user_id) do
    initial_state = %{
      id: playthrough_id,
      user_id: user_id,
      media_id: nil,
      status: nil,
      started_at: nil,
      finished_at: nil,
      abandoned_at: nil,
      deleted_at: nil,
      position: nil,
      rate: nil,
      last_event_at: nil,
      refreshed_at: DateTime.utc_now()
    }

    events
    |> Enum.reduce(initial_state, &apply_event/2)
  end

  defp apply_event(event, state) do
    state
    |> update_last_event_at(event)
    |> apply_event_type(event)
  end

  defp update_last_event_at(state, event) do
    %{state | last_event_at: event.timestamp}
  end

  # Lifecycle events
  defp apply_event_type(state, %{type: :start} = event) do
    %{
      state
      | status: :in_progress,
        started_at: event.timestamp,
        media_id: event.media_id,
        position: event.position,
        rate: event.playback_rate
    }
  end

  defp apply_event_type(state, %{type: :finish} = event) do
    %{state | status: :finished, finished_at: event.timestamp}
  end

  defp apply_event_type(state, %{type: :abandon} = event) do
    %{state | status: :abandoned, abandoned_at: event.timestamp}
  end

  defp apply_event_type(state, %{type: :delete} = event) do
    %{state | status: :deleted, deleted_at: event.timestamp}
  end

  defp apply_event_type(state, %{type: :resume}) do
    %{state | status: :in_progress, finished_at: nil, abandoned_at: nil, deleted_at: nil}
  end

  # Playback events
  defp apply_event_type(state, %{type: :play} = event) do
    %{state | position: event.position}
  end

  defp apply_event_type(state, %{type: :pause} = event) do
    %{state | position: event.position}
  end

  defp apply_event_type(state, %{type: :seek} = event) do
    %{state | position: event.to_position}
  end

  defp apply_event_type(state, %{type: :rate_change} = event) do
    %{state | rate: event.playback_rate}
  end

  # Fallback for unknown event types
  defp apply_event_type(state, _event), do: state
end
