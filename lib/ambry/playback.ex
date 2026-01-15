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
      PlaybackEvent
    ]

  import Ecto.Query

  alias Ambry.Playback.Device
  alias Ambry.Playback.PlaybackEvent
  alias Ambry.Playback.Playthrough
  alias Ambry.Repo

  ## Devices

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

  ## Playback Events

  @doc """
  Records multiple playback events in a single transaction.

  Returns `{:ok, count}` with number of events inserted.
  """
  def record_events(events_attrs) when is_list(events_attrs) do
    now = DateTime.utc_now()

    events =
      Enum.map(events_attrs, fn attrs ->
        timestamp = attrs[:timestamp] || attrs["timestamp"]

        %{
          id: attrs[:id] || attrs["id"],
          playthrough_id: attrs[:playthrough_id] || attrs["playthrough_id"],
          device_id: attrs[:device_id] || attrs["device_id"],
          type: attrs[:type] || attrs["type"],
          timestamp: timestamp,
          position: attrs[:position] || attrs["position"],
          playback_rate: attrs[:playback_rate] || attrs["playback_rate"],
          from_position: attrs[:from_position] || attrs["from_position"],
          to_position: attrs[:to_position] || attrs["to_position"],
          previous_rate: attrs[:previous_rate] || attrs["previous_rate"],
          inserted_at: now
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

  @doc """
  Syncs events from a client.

  Accepts a list of event data and records them.
  Returns `{:ok, count}` with number of events synced.
  """
  def sync_events(events_data) when is_list(events_data) do
    record_events(events_data)
  end
end
