defmodule Ambry.Playback.PlaybackEvent do
  @moduledoc """
  Immutable record of something that happened during playback.

  Events are the source of truth for playback state. The current position,
  playback rate, and listening statistics are all derived from the event stream.

  ## Event Types

  ### Playback Events (have position and playback_rate)
  - `play`: User started/resumed playback
  - `pause`: User paused
  - `seek`: User jumped from `from_position` to `to_position`
  - `rate_change`: User changed speed from `previous_rate` to `playback_rate`

  ### Lifecycle Events (no position/rate - semantic markers only)
  - `start`: Playthrough started
  - `finish`: Playthrough marked as finished (auto-detected or manual)
  - `abandon`: User explicitly abandoned the playthrough
  - `resume`: User resumed a previously finished or abandoned playthrough

  Lifecycle events are semantic markers about the playthrough status, not playback
  state changes. A user might "finish" a book while at any position (e.g., after
  re-listening to highlights). Multiple finish events can occur if a user resumes
  a finished playthrough and finishes again.

  ## Derived State

  From playback events (not lifecycle events), we can compute:
  - Current position: position from most recent playback event
  - Current rate: playback_rate from most recent playback event
  - Total listening time: sum of (pause.position - play.position) / playback_rate
  - Session count: grouping events with 30 min gaps
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.Media
  alias Ambry.Playback.Device
  alias Ambry.Playback.Playthrough

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @event_types [:start, :play, :pause, :seek, :rate_change, :finish, :abandon, :resume, :delete]
  @playback_event_types [:play, :pause, :seek, :rate_change]
  @lifecycle_event_types [:start, :finish, :abandon, :resume, :delete]

  schema "playback_events" do
    belongs_to :playthrough, Playthrough
    belongs_to :device, Device
    belongs_to :media, Media, type: :id

    field :type, Ecto.Enum, values: @event_types
    field :timestamp, Ambry.Ecto.UtcDateTimeMs
    field :position, :decimal
    field :playback_rate, :decimal

    # seek-specific fields
    field :from_position, :decimal
    field :to_position, :decimal

    # rate_change-specific field
    field :previous_rate, :decimal

    # Events are immutable, so no updated_at. inserted_at is used for sync cursoring
    # (distinct from `timestamp` which is when the event occurred on the client).
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Returns the list of valid event types.
  """
  def event_types, do: @event_types

  @doc """
  Returns the list of playback event types (have position/rate).
  """
  def playback_event_types, do: @playback_event_types

  @doc """
  Returns the list of lifecycle event types (no position/rate).
  """
  def lifecycle_event_types, do: @lifecycle_event_types

  @doc """
  Creates a changeset for a new playback event.

  Requires a client-generated UUID as the id.

  Playback events (play, pause, seek, rate_change) require position and playback_rate.
  Lifecycle events (start, finish, abandon) do not use position/rate fields.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :playthrough_id,
      :device_id,
      :media_id,
      :type,
      :timestamp,
      :position,
      :playback_rate,
      :from_position,
      :to_position,
      :previous_rate
    ])
    |> validate_required([
      :id,
      :playthrough_id,
      :type,
      :timestamp
    ])
    |> validate_type_specific_fields()
  end

  defp validate_type_specific_fields(changeset) do
    type = get_field(changeset, :type)

    cond do
      type in @playback_event_types ->
        changeset
        |> validate_required([:position, :playback_rate])
        |> validate_playback_event_fields(type)

      type == :start ->
        # Start events require media_id to identify what is being played, as well as default position/rate
        changeset
        |> validate_required([:media_id, :position, :playback_rate])

      type in @lifecycle_event_types ->
        # Other lifecycle events don't need position/rate or media_id
        changeset

      true ->
        changeset
    end
  end

  defp validate_playback_event_fields(changeset, :seek) do
    changeset
    |> validate_required([:from_position, :to_position])
  end

  defp validate_playback_event_fields(changeset, :rate_change) do
    changeset
    |> validate_required([:previous_rate])
  end

  defp validate_playback_event_fields(changeset, _type), do: changeset
end
