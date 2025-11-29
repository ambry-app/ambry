defmodule Ambry.Playback do
  @moduledoc """
  Context for managing playback state via event sourcing.

  This module provides functions for:
  - Managing playthroughs (user journeys through media)
  - Recording playback events (play, pause, seek, etc.)
  - Registering and managing devices
  - Deriving current state from event streams
  - Syncing events between client and server

  ## Key Concepts

  - **Playthrough**: A user's journey through a book (days/weeks/months)
  - **PlaybackEvent**: Immutable record of a playback action
  - **Device**: Client device that produces events

  ## State Derivation

  Current playback state is derived from the event stream:
  - Position: from most recent event
  - Rate: from most recent event
  - Listening time: sum of (pause.position - play.position) / rate
  """

  use Boundary,
    deps: [Ambry],
    exports: [
      Device,
      Playthrough,
      PlaybackEvent
    ]

  import Ecto.Query

  alias Ambry.Playback.Device
  alias Ambry.Playback.PlaybackEvent
  alias Ambry.Playback.Playthrough
  alias Ambry.Repo

  # ============================================================================
  # Devices
  # ============================================================================

  @doc """
  Registers a new device or updates an existing one.

  Uses upsert semantics - if device with ID exists, updates last_seen_at.
  """
  def register_device(attrs) do
    changeset = Device.changeset(%Device{}, attrs)

    Repo.insert(changeset,
      on_conflict: {:replace, [:last_seen_at, :updated_at]},
      conflict_target: :id,
      returning: true
    )
  end

  @doc """
  Gets a device by ID.

  Returns `{:ok, device}` or `{:error, :not_found}`.
  """
  def get_device(id) do
    case Repo.get(Device, id) do
      nil -> {:error, :not_found}
      device -> {:ok, device}
    end
  end

  @doc """
  Lists all devices for a user.
  """
  def list_devices(user_id) do
    Device
    |> where([d], d.user_id == ^user_id)
    |> order_by([d], desc: d.last_seen_at)
    |> Repo.all()
  end

  # ============================================================================
  # Playthroughs
  # ============================================================================

  @doc """
  Creates a new playthrough or updates an existing one.

  Uses upsert semantics based on the client-generated ID.
  """
  def upsert_playthrough(attrs) do
    changeset = Playthrough.changeset(%Playthrough{}, attrs)

    Repo.insert(changeset,
      on_conflict: {:replace, [:status, :finished_at, :abandoned_at, :deleted_at, :updated_at]},
      conflict_target: :id,
      returning: true
    )
  end

  @doc """
  Gets the active (in_progress) playthrough for a user and media.

  Returns `nil` if no active playthrough exists.
  """
  def get_active_playthrough(user_id, media_id) do
    Playthrough
    |> where([p], p.user_id == ^user_id and p.media_id == ^media_id and p.status == :in_progress)
    |> Repo.one()
  end

  @doc """
  Gets a playthrough by ID.

  Returns `{:ok, playthrough}` or `{:error, :not_found}`.
  """
  def get_playthrough(id) do
    case Repo.get(Playthrough, id) do
      nil -> {:error, :not_found}
      playthrough -> {:ok, playthrough}
    end
  end

  @doc """
  Gets a playthrough by ID, raising if not found.
  """
  def get_playthrough!(id) do
    Repo.get!(Playthrough, id)
  end

  @doc """
  Lists all playthroughs for a user.

  Optionally filtered by status.
  """
  def list_playthroughs(user_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      Playthrough
      |> where([p], p.user_id == ^user_id)
      |> order_by([p], desc: p.updated_at)
      |> limit(^limit)
      |> offset(^offset)

    query =
      if status do
        where(query, [p], p.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Lists playthroughs changed since a given timestamp.

  Used for sync - returns playthroughs updated after the given time.
  """
  def list_playthroughs_changed_since(user_id, since) do
    Playthrough
    |> where([p], p.user_id == ^user_id and p.updated_at > ^since)
    |> order_by([p], asc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Finishes a playthrough.
  """
  def finish_playthrough(%Playthrough{} = playthrough) do
    playthrough
    |> Playthrough.finish_changeset()
    |> Repo.update()
  end

  @doc """
  Abandons a playthrough.
  """
  def abandon_playthrough(%Playthrough{} = playthrough) do
    playthrough
    |> Playthrough.abandon_changeset()
    |> Repo.update()
  end

  @doc """
  Soft-deletes a playthrough.

  Sets `deleted_at` timestamp for sync purposes. The playthrough and its
  events remain in the database but are filtered out of normal queries.
  """
  def delete_playthrough(%Playthrough{} = playthrough) do
    playthrough
    |> Playthrough.delete_changeset()
    |> Repo.update()
  end

  @doc """
  Resumes a finished or abandoned playthrough.

  Reverts status to `in_progress` and clears `finished_at`/`abandoned_at`.
  The user continues from their last position (derived from playback events).
  """
  def resume_playthrough(%Playthrough{} = playthrough) do
    playthrough
    |> Playthrough.resume_changeset()
    |> Repo.update()
  end

  # ============================================================================
  # Playback Events
  # ============================================================================

  @doc """
  Records a playback event.

  Events are immutable - this always inserts, never updates.
  Uses ON CONFLICT DO NOTHING for idempotent upserts.
  """
  def record_event(attrs) do
    changeset = PlaybackEvent.changeset(%PlaybackEvent{}, attrs)

    Repo.insert(changeset,
      on_conflict: :nothing,
      returning: true
    )
  end

  @doc """
  Records multiple playback events in a single transaction.

  Returns `{:ok, count}` with number of events inserted.
  """
  def record_events(events_attrs) when is_list(events_attrs) do
    events =
      Enum.map(events_attrs, fn attrs ->
        %{
          id: attrs[:id] || attrs["id"],
          playthrough_id: attrs[:playthrough_id] || attrs["playthrough_id"],
          device_id: attrs[:device_id] || attrs["device_id"],
          type: attrs[:type] || attrs["type"],
          timestamp: attrs[:timestamp] || attrs["timestamp"],
          position: attrs[:position] || attrs["position"],
          playback_rate: attrs[:playback_rate] || attrs["playback_rate"],
          from_position: attrs[:from_position] || attrs["from_position"],
          to_position: attrs[:to_position] || attrs["to_position"],
          previous_rate: attrs[:previous_rate] || attrs["previous_rate"]
        }
      end)

    {count, _} =
      Repo.insert_all(PlaybackEvent, events,
        on_conflict: :nothing,
        returning: false
      )

    {:ok, count}
  end

  @doc """
  Gets all events for a playthrough, ordered by timestamp.
  """
  def list_events(playthrough_id) do
    PlaybackEvent
    |> where([e], e.playthrough_id == ^playthrough_id)
    |> order_by([e], asc: e.timestamp)
    |> Repo.all()
  end

  @doc """
  Gets the most recent event for a playthrough.
  """
  def get_latest_event(playthrough_id) do
    PlaybackEvent
    |> where([e], e.playthrough_id == ^playthrough_id)
    |> order_by([e], desc: e.timestamp)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Lists events changed since a given timestamp.

  Used for sync - returns events with timestamp after the given time.
  Note: Events are immutable, so "changed" means "created after".
  """
  def list_events_changed_since(user_id, since) do
    PlaybackEvent
    |> join(:inner, [e], p in Playthrough, on: e.playthrough_id == p.id)
    |> where([e, p], p.user_id == ^user_id and e.timestamp > ^since)
    |> order_by([e], asc: e.timestamp)
    |> select([e], e)
    |> Repo.all()
  end

  # ============================================================================
  # State Derivation
  # ============================================================================

  @doc """
  Derives the current state for a playthrough from its event stream.

  Returns a map with:
  - `:position` - current position in seconds
  - `:playback_rate` - current playback rate
  - `:last_event_at` - timestamp of most recent event
  - `:total_listening_time` - calculated real listening time

  Note: Only playback events (play, pause, seek, rate_change) are used for
  position/rate derivation. Lifecycle events (start, finish, abandon) don't
  have position data.
  """
  def derive_state(playthrough_id) do
    events = list_events(playthrough_id)
    playback_events = Enum.filter(events, &(&1.type in PlaybackEvent.playback_event_types()))

    case playback_events do
      [] ->
        %{
          position: Decimal.new(0),
          playback_rate: Decimal.new(1),
          last_event_at: nil,
          total_listening_time: Decimal.new(0)
        }

      playback_events ->
        latest = List.last(playback_events)

        %{
          position: latest.position,
          playback_rate: latest.playback_rate,
          last_event_at: latest.timestamp,
          total_listening_time: calculate_listening_time(playback_events)
        }
    end
  end

  @doc """
  Calculates total listening time from a list of events.

  Listening time is calculated as the sum of time between play and pause events,
  divided by the playback rate active during that segment.
  """
  def calculate_listening_time(events) do
    events
    |> Enum.reduce({nil, Decimal.new(0)}, fn event, {play_event, total} ->
      case {event.type, play_event} do
        # Start of a play segment
        {:play, nil} ->
          {event, total}

        # End of a play segment - calculate duration
        {:pause, %{position: start_pos, playback_rate: rate}} ->
          duration = Decimal.sub(event.position, start_pos)
          # Adjust for playback rate (listening at 2x means half the real time)
          real_time = Decimal.div(duration, rate)
          {nil, Decimal.add(total, real_time)}

        # Ignore other events for listening time calculation
        _ ->
          {play_event, total}
      end
    end)
    |> elem(1)
  end

  # ============================================================================
  # Sync Helpers
  # ============================================================================

  @doc """
  Syncs playthroughs from a client.

  Accepts a list of playthrough data and upserts them.
  Returns the list of synced playthroughs.
  """
  def sync_playthroughs(playthroughs_data) when is_list(playthroughs_data) do
    Enum.map(playthroughs_data, fn data ->
      case upsert_playthrough(data) do
        {:ok, playthrough} -> playthrough
        {:error, _changeset} -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  @doc """
  Syncs events from a client.

  Accepts a list of event data and records them.
  Returns `{:ok, count}` with number of events synced.
  """
  def sync_events(events_data) when is_list(events_data) do
    record_events(events_data)
  end
end
