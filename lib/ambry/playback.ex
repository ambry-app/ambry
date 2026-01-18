defmodule Ambry.Playback do
  @moduledoc """
  Context for managing playback state via event sourcing.

  This module provides functions for:
  - Registering devices
  - Syncing playthroughs and events between client and server

  ## Key Concepts

  - **Playthrough**: A user's journey through a book (days/weeks/months)
  - **PlaybackEvent**: Immutable record of a playback action
  - **Device**: Client device that produces events
  """

  use Boundary,
    deps: [Ambry],
    exports: [
      Device,
      Playthrough,
      PlaythroughNew,
      PlaybackEvent
    ]

  import Ecto.Query

  alias Ambry.Playback.Device
  alias Ambry.Playback.PlaybackEvent
  alias Ambry.Playback.Playthrough
  alias Ambry.Playback.PlaythroughNew
  alias Ambry.Repo

  ## Devices

  @doc """
  Registers a new device or updates an existing one.

  Uses upsert semantics - if device with ID exists, updates all fields except
  id, user_id, and inserted_at. This ensures fields that change over time
  (os_version, app_version, etc.) stay current.
  """
  def register_device(attrs) do
    changeset = Device.changeset(%Device{}, attrs)

    Repo.insert(changeset,
      on_conflict: {:replace_all_except, [:id, :user_id, :inserted_at]},
      conflict_target: :id,
      returning: true
    )
  end

  ## Playthroughs

  @doc """
  Upserts a playthrough based on client-generated UUID.

  If a playthrough with the same ID exists, updates it.
  Otherwise, creates a new playthrough (even if duplicate from migration edge case).
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
  Lists all playthroughs for a user (no pagination).

  Used for initial sync when a fresh device needs all data.
  """
  def list_all_playthroughs(user_id) do
    Playthrough
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], asc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Rebuilds all playthroughs in the `playthroughs_new` table from their events.

  This is useful for migrations or repairs where the derived state needs to be
  re-calculated from the source of truth (the events).
  """
  def rebuild_all_playthroughs do
    # Get all playthrough and user IDs from the new table
    query =
      from(pn in PlaythroughNew,
        select: {pn.id, pn.user_id}
      )

    Repo.all(query)
    |> Enum.each(fn {playthrough_id, user_id} ->
      rebuild_playthrough_new(playthrough_id, user_id)
    end)

    :ok
  end

  ## Playback Events

  @doc """
  Records multiple playback events in a single transaction.

  Also rebuilds the derived playthrough state in `playthroughs_new` for any
  affected playthroughs.

  Returns `{:ok, count}` with number of events inserted.
  """
  def record_events(events_attrs, user_id) do
    events_attrs =
      Enum.map(events_attrs, fn attrs ->
        Map.put(attrs, :inserted_at, {:placeholder, :now})
      end)

    {count, _} =
      Repo.insert_all(PlaybackEvent, events_attrs,
        on_conflict: :nothing,
        returning: false,
        placeholders: %{now: DateTime.utc_now()}
      )

    # Rebuild derived state for affected playthroughs
    playthrough_ids =
      events_attrs
      |> Enum.map(&(&1[:playthrough_id] || &1["playthrough_id"]))
      |> Enum.uniq()

    Enum.each(playthrough_ids, &rebuild_playthrough_new(&1, user_id))

    {:ok, count}
  end

  defp rebuild_playthrough_new(playthrough_id, user_id) do
    # Fetch all events for this playthrough, sorted by timestamp
    events =
      PlaybackEvent
      |> where([e], e.playthrough_id == ^playthrough_id)
      |> order_by([e], asc: e.timestamp)
      |> Repo.all()

    if events != [] do
      # Reduce events to derive state
      state = PlaythroughNew.reduce(events, playthrough_id, user_id)

      # Upsert into playthroughs_new
      Repo.insert_all(
        PlaythroughNew,
        [state],
        on_conflict: {:replace_all_except, [:id]},
        conflict_target: :id
      )
    end
  end

  @doc """
  Lists events inserted since a given timestamp.

  Used for sync - returns events inserted after the given time.
  Uses `inserted_at` (when recorded) rather than `timestamp` (when occurred)
  so that synthesized historical events can be synced to clients.
  """
  def list_events_changed_since(user_id, since) do
    PlaybackEvent
    |> join(:inner, [e], p in Playthrough, on: e.playthrough_id == p.id)
    |> where([e, p], p.user_id == ^user_id and e.inserted_at > ^since)
    |> order_by([e], asc: e.inserted_at)
    |> select([e], e)
    |> Repo.all()
  end

  @doc """
  Lists all events for a user's playthroughs (no pagination).

  Used for initial sync when a fresh device needs all data.
  """
  def list_all_events(user_id) do
    PlaybackEvent
    |> join(:inner, [e], p in Playthrough, on: e.playthrough_id == p.id)
    |> where([_e, p], p.user_id == ^user_id)
    |> order_by([e], asc: e.timestamp)
    |> select([e], e)
    |> Repo.all()
  end

  @doc """
  V2: Lists events changed since the given time, using playthroughs_new.

  For V2 sync which doesn't use the legacy playthroughs table.
  """
  def list_events_changed_since_v2(user_id, since) do
    PlaybackEvent
    |> join(:inner, [e], p in PlaythroughNew, on: e.playthrough_id == p.id)
    |> where([e, p], p.user_id == ^user_id and e.inserted_at > ^since)
    |> order_by([e], asc: e.inserted_at)
    |> select([e], e)
    |> Repo.all()
  end

  @doc """
  V2: Lists all events for a user, using playthroughs_new.

  For V2 sync which doesn't use the legacy playthroughs table.
  """
  def list_all_events_v2(user_id) do
    PlaybackEvent
    |> join(:inner, [e], p in PlaythroughNew, on: e.playthrough_id == p.id)
    |> where([_e, p], p.user_id == ^user_id)
    |> order_by([e], asc: e.timestamp)
    |> select([e], e)
    |> Repo.all()
  end

  ## Sync Helpers

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
end
