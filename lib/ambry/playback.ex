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
      DeviceFlat,
      DeviceUser,
      Playthrough,
      PlaythroughFlat,
      PlaybackEvent
    ]

  import Ecto.Query

  alias Ambry.Playback.Device
  alias Ambry.Playback.DeviceFlat
  alias Ambry.Playback.DeviceUser
  alias Ambry.Playback.PlaybackEvent
  alias Ambry.Playback.Playthrough
  alias Ambry.Playback.PlaythroughFlat
  alias Ambry.Repo

  ## Devices

  @doc """
  Registers a device and links it to a user.

  Upserts the device metadata and creates/updates the device-user link.
  Returns `{:ok, device}` on success.

  This function:
  1. Upserts the device record (metadata like OS, app version, etc.)
  2. Upserts the device-user link with updated last_seen_at
  """
  def register_device(attrs) do
    {user_id, device_attrs} = Map.pop(attrs, :user_id)

    Repo.transaction(fn ->
      device_changeset = Device.changeset(%Device{}, device_attrs)

      {:ok, device} =
        Repo.insert(device_changeset,
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: :id,
          returning: true
        )

      # Upsert the device-user link
      link_attrs = %{
        device_id: device.id,
        user_id: user_id,
        last_seen_at: DateTime.utc_now()
      }

      link_changeset = DeviceUser.changeset(%DeviceUser{}, link_attrs)

      Repo.insert(link_changeset,
        on_conflict: [set: [last_seen_at: DateTime.utc_now()]],
        conflict_target: [:device_id, :user_id]
      )

      device
    end)
  end

  ## Playthroughs

  @doc """
  Lists playthroughs from the flat view with filtering, sorting, and pagination.
  """
  def list_playthroughs_flat(offset, limit, filters, order_by) do
    limit_plus_one = limit + 1

    results =
      PlaythroughFlat
      |> PlaythroughFlat.filter(filters)
      |> PlaythroughFlat.order(order_by)
      |> limit(^limit_plus_one)
      |> offset(^offset)
      |> Repo.all()

    if length(results) > limit do
      {Enum.slice(results, 0, limit), true}
    else
      {results, false}
    end
  end

  @doc """
  How many playthroughs a list would have, under the filters it lists with.
  """
  def count_playthroughs_flat(filters) do
    filters |> PlaythroughFlat.count_query() |> Repo.one()
  end

  @doc """
  Lists devices from the flat view with filtering, sorting, and pagination.
  """
  def list_devices_flat(offset, limit, filters, order_by) do
    limit_plus_one = limit + 1

    results =
      DeviceFlat
      |> DeviceFlat.filter(filters)
      |> DeviceFlat.order(order_by)
      |> limit(^limit_plus_one)
      |> offset(^offset)
      |> Repo.all()

    if length(results) > limit do
      {Enum.slice(results, 0, limit), true}
    else
      {results, false}
    end
  end

  @doc """
  How many devices a list would have, under the filters it lists with.
  """
  def count_devices_flat(filters) do
    filters |> DeviceFlat.count_query() |> Repo.one()
  end

  @doc """
  Gets a single playthrough by ID with preloads.
  """
  def get_playthrough(id) do
    from(p in Playthrough,
      where: p.id == ^id,
      preload: [[media: :book], :user]
    )
    |> Repo.one()
  end

  @doc """
  Rebuilds all playthroughs in the `playthroughs` table from their events.

  This is useful for migrations or repairs where the derived state needs to be
  re-calculated from the source of truth (the events).
  """
  def rebuild_all_playthroughs do
    query =
      from(pn in Playthrough,
        select: {pn.id, pn.user_id}
      )

    Repo.all(query)
    |> Enum.each(fn {playthrough_id, user_id} ->
      rebuild_playthrough(playthrough_id, user_id)
    end)

    :ok
  end

  ## Playback Events

  @doc """
  Records multiple playback events in a single transaction.

  Also rebuilds the derived playthrough state in `playthroughs` for any
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

    playthrough_ids =
      events_attrs
      |> Enum.map(&(&1[:playthrough_id] || &1["playthrough_id"]))
      |> Enum.uniq()

    Enum.each(playthrough_ids, &rebuild_playthrough(&1, user_id))

    {:ok, count}
  end

  defp rebuild_playthrough(playthrough_id, user_id) do
    # Fetch all events for this playthrough, sorted by timestamp
    events =
      PlaybackEvent
      |> where([e], e.playthrough_id == ^playthrough_id)
      |> order_by([e], asc: e.timestamp)
      |> Repo.all()

    if events != [] do
      # Reduce events to derive state
      state = Playthrough.reduce(events, playthrough_id, user_id)

      # Upsert into playthroughs
      Repo.insert_all(
        Playthrough,
        [state],
        on_conflict: {:replace_all_except, [:id]},
        conflict_target: :id
      )
    end
  end

  @doc """
  Lists events changed since the given time.

  Used for sync - uses `inserted_at` (when recorded) rather than `timestamp`
  (when occurred) so that synthesized historical events reach clients.
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
  Lists all events for a user (no pagination).

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
end
