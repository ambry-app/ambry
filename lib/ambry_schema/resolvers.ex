defmodule AmbrySchema.Resolvers do
  @moduledoc false

  import Absinthe.Relay.Node, only: [from_global_id: 2]
  import Absinthe.Resolution.Helpers, only: [batch: 3]
  import Ecto.Query

  alias Absinthe.Relay.Connection
  alias Ambry.Accounts
  alias Ambry.Accounts.User
  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Books.SeriesBook
  alias Ambry.Deletions.Deletion
  alias Ambry.Hashids
  alias Ambry.Media.Media
  alias Ambry.Media.MediaNarrator
  alias Ambry.Media.PlayerState
  alias Ambry.People.Author
  alias Ambry.People.BookAuthor
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Playback
  alias Ambry.Repo
  alias Ambry.Search
  alias Ambry.Sync

  def create_session(%{email: email, password: password}, _resolution) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      token = Accounts.generate_user_session_token(user)

      {:ok, %{token: Base.url_encode64(token), user: user}}
    else
      {:error, "invalid username or password"}
    end
  end

  def delete_session(_args, %{context: context}) do
    user_token = context[:current_user_token]
    user_token && Accounts.delete_user_session_token(user_token)

    {:ok, %{deleted: true}}
  end

  def current_user(_args, %{context: %{current_user: user}}), do: {:ok, user}
  def current_user(_args, _resolution), do: {:ok, nil}

  def list_books(args, _resolution) do
    Book
    |> order_by({:desc, :inserted_at})
    |> Connection.from_query(&Repo.all/1, args)
  end

  def list_authored_books(%Author{} = author, args, _resolution) do
    author
    |> Ecto.assoc(:books)
    |> order_by({:desc, :published})
    |> Connection.from_query(&Repo.all/1, args)
  end

  def list_narrated_media(%Narrator{} = narrator, args, _resolution) do
    query =
      from m in Ecto.assoc(narrator, :media),
        order_by: [desc: :published]

    Connection.from_query(query, &Repo.all/1, args)
  end

  def list_player_states(args, %{context: %{current_user: %User{} = user}}) do
    user
    |> Ecto.assoc(:player_states)
    |> where(status: :in_progress)
    |> order_by({:desc, :updated_at})
    |> Connection.from_query(&Repo.all/1, args)
  end

  def search(%{query: query} = args, _resolution) do
    query_string = String.trim(query)

    if String.length(query_string) < 3 do
      {:error, "query must be at least 3 characters"}
    else
      query_string
      |> Search.query()
      |> Connection.from_query(&Search.all/1, args)
    end
  end

  def people_changed_since(args, _resolution), do: Sync.changes_since(Person, args[:since])
  def authors_changed_since(args, _resolution), do: Sync.changes_since(Author, args[:since])
  def narrators_changed_since(args, _resolution), do: Sync.changes_since(Narrator, args[:since])
  def books_changed_since(args, _resolution), do: Sync.changes_since(Book, args[:since])

  def book_authors_changed_since(args, _resolution),
    do: Sync.changes_since(BookAuthor, args[:since])

  def series_changed_since(args, _resolution), do: Sync.changes_since(Series, args[:since])

  def series_books_changed_since(args, _resolution),
    do: Sync.changes_since(SeriesBook, args[:since])

  def media_changed_since(args, _resolution), do: Sync.changes_since(Media, args[:since])

  def media_narrators_changed_since(args, _resolution),
    do: Sync.changes_since(MediaNarrator, args[:since])

  def player_states_changed_since(args, %{context: %{current_user: %User{} = user}}),
    do: Sync.changes_since(from(ps in PlayerState, where: ps.user_id == ^user.id), args[:since])

  def deletions_since(args, _resolution), do: Sync.deletions_since(args[:since])

  def load_player_state(%{media_id: media_id}, %{context: %{current_user: %User{} = user}}) do
    with {:ok, %{id: media_id, type: :media}} <- from_global_id(media_id, AmbrySchema) do
      media_id = String.to_integer(media_id)
      player_state = Ambry.Media.get_player_state!(user.id, media_id)
      {:ok, %{player_state: player_state}}
    end
  end

  def update_player_state(%{media_id: media_id} = args, %{
        context: %{current_user: %User{} = user}
      }) do
    with {:ok, %{id: media_id, type: :media}} <- from_global_id(media_id, AmbrySchema),
         media_id = String.to_integer(media_id),
         %{position: position, playback_rate: playback_rate} = args,
         {:ok, player_state} <-
           Ambry.Media.update_player_state(user.id, media_id, position, playback_rate) do
      {:ok, %{player_state: player_state}}
    end
  end

  def list_series_books(%Series{} = series, args, _resolution) do
    series
    |> Ecto.assoc(:series_books)
    |> order_by({:asc, :book_number})
    |> Connection.from_query(&Repo.all/1, args)
  end

  def chapters(%Media{chapters: chapters}, _args, _resolution) do
    {:ok,
     chapters
     |> Enum.chunk_every(2, 1)
     |> Enum.with_index()
     |> Enum.map(fn
       {[chapter, next], idx} ->
         %{
           id: Hashids.encode(idx),
           title: chapter.title,
           start_time: chapter.time |> Decimal.round(2) |> Decimal.to_float(),
           end_time: next.time |> Decimal.round(2) |> Decimal.to_float()
         }

       {[last_chapter], idx} ->
         %{
           id: Hashids.encode(idx),
           title: last_chapter.title,
           start_time: last_chapter.time |> Decimal.round(2) |> Decimal.to_float(),
           end_time: nil
         }
     end)}
  end

  def resolve_decimal(key) do
    fn
      %{^key => nil}, _args, _resolution ->
        {:ok, nil}

      %{^key => value}, _args, _resolution ->
        {:ok, Decimal.to_float(value)}
    end
  end

  def node(%{type: :author, id: id}, _resolution), do: {:ok, Repo.get(Author, id)}
  def node(%{type: :book, id: id}, _resolution), do: {:ok, Repo.get(Book, id)}
  def node(%{type: :book_author, id: id}, _resolution), do: {:ok, Repo.get(BookAuthor, id)}
  def node(%{type: :deletion, id: id}, _resolution), do: {:ok, Repo.get(Deletion, id)}
  def node(%{type: :media, id: id}, _resolution), do: {:ok, Repo.get(Media, id)}
  def node(%{type: :media_narrator, id: id}, _resolution), do: {:ok, Repo.get(MediaNarrator, id)}
  def node(%{type: :narrator, id: id}, _resolution), do: {:ok, Repo.get(Narrator, id)}
  def node(%{type: :person, id: id}, _resolution), do: {:ok, Repo.get(Person, id)}
  def node(%{type: :series, id: id}, _resolution), do: {:ok, Repo.get(Series, id)}
  def node(%{type: :series_book, id: id}, _resolution), do: {:ok, Repo.get(SeriesBook, id)}

  def node(%{type: :player_state, id: id}, %{context: %{current_user: %User{id: user_id}}}) do
    query = from ps in PlayerState, where: ps.user_id == ^user_id
    {:ok, Repo.get(query, id)}
  end

  def type(%Author{}, _resolution), do: :author
  def type(%Book{}, _resolution), do: :book
  def type(%BookAuthor{}, _resolution), do: :book_author
  def type(%Deletion{}, _resolution), do: :deletion
  def type(%Media{}, _resolution), do: :media
  def type(%MediaNarrator{}, _resolution), do: :media_narrator
  def type(%Narrator{}, _resolution), do: :narrator
  def type(%Person{}, _resolution), do: :person
  def type(%PlayerState{}, _resolution), do: :player_state
  def type(%Series{}, _resolution), do: :series
  def type(%SeriesBook{}, _resolution), do: :series_book

  ## Custom batches

  def player_state_batch(%Media{id: media_id}, _params, %{
        context: %{current_user: %User{id: user_id}}
      }) do
    batch({__MODULE__, :player_states, user_id}, media_id, fn batch_results ->
      {:ok, Map.get(batch_results, media_id)}
    end)
  end

  def player_states(user_id, media_ids) do
    query = from ps in PlayerState, where: ps.user_id == ^user_id and ps.media_id in ^media_ids

    query
    |> Repo.all()
    # NOTE: There should never be more than one player state per media per user.
    |> Map.new(&{&1.media_id, &1})
  end

  ## Playback Sync

  @doc """
  Handles bidirectional sync of playback progress.

  1. Registers/updates the device
  2. Upserts playthroughs from client (with user_id from context)
  3. Records events from client
  4. Returns all data changed since lastSyncTime
  """
  def sync_progress(%{input: input}, %{context: %{current_user: %User{id: user_id}}}) do
    %{
      device: device_input,
      playthroughs: playthroughs_input,
      events: events_input,
      last_sync_time: last_sync_time
    } = input

    # 1. Register/update device
    device_attrs = Map.put(device_input, :user_id, user_id)
    {:ok, device} = Playback.register_device(device_attrs)

    # 2. Upsert playthroughs from client
    playthroughs_data =
      Enum.map(playthroughs_input, fn playthrough ->
        # Decode media_id from global ID
        {:ok, %{id: media_id_str}} = from_global_id(playthrough.media_id, AmbrySchema)
        media_id = String.to_integer(media_id_str)

        playthrough
        |> Map.put(:user_id, user_id)
        |> Map.put(:media_id, media_id)
      end)

    Playback.sync_playthroughs(playthroughs_data)

    # Build lookup of media_id from upserted playthroughs (for backfilling start
    # events) Legacy clients don't send media_id on start events
    media_id_lookup = Map.new(playthroughs_data, &{&1.id, &1.media_id})

    # Build lookup of playback_rate from play events (for backfilling start
    # events) Legacy clients don't send rate on start events but do on the first
    # play event
    play_rate_lookup =
      events_input
      |> Enum.filter(&(&1.type == :play && &1[:playback_rate]))
      |> Map.new(&{&1.playthrough_id, &1.playback_rate})

    # 3. Synthesize lifecycle events for playthroughs.
    #    Legacy clients may sync playthroughs without events (e.g., during initial migration).
    #    We synthesize start events to ensure playthroughs_new has a valid media_id.
    #    Legacy clients also don't send delete events but do send deleted_at on playthroughs,
    #    so we synthesize delete events so the event-sourced system sees the deletion.

    # Find which playthroughs already have a start event in the input
    playthroughs_with_start =
      events_input
      |> Enum.filter(&(&1.type == :start))
      |> MapSet.new(& &1.playthrough_id)

    synthetic_start_events =
      playthroughs_data
      |> Enum.reject(&MapSet.member?(playthroughs_with_start, &1.id))
      |> Enum.map(fn playthrough ->
        playback_rate = Map.get(play_rate_lookup, playthrough.id, 1.0)

        %{
          id: deterministic_start_event_id(playthrough.id),
          playthrough_id: playthrough.id,
          device_id: device.id,
          type: :start,
          timestamp: playthrough.started_at,
          media_id: playthrough.media_id,
          position: 0.0,
          playback_rate: playback_rate,
          app_version: device.app_version,
          app_build: device.app_build
        }
      end)

    synthetic_delete_events =
      playthroughs_data
      |> Enum.filter(&(&1[:deleted_at] != nil))
      |> Enum.map(fn playthrough ->
        %{
          id: deterministic_delete_event_id(playthrough.id),
          playthrough_id: playthrough.id,
          device_id: device.id,
          type: :delete,
          timestamp: playthrough.deleted_at,
          app_version: device.app_version,
          app_build: device.app_build
        }
      end)

    synthetic_events = synthetic_start_events ++ synthetic_delete_events

    # 4. Record events from client (with device_id and app info from registered device),
    #    backfilling media_id, position, and playback_rate for :start events
    events_data =
      Enum.map(events_input, fn event ->
        event
        |> Map.put(:device_id, device.id)
        |> Map.put(:app_version, device.app_version)
        |> Map.put(:app_build, device.app_build)
        |> then(fn
          %{type: :start} = event ->
            media_id = Map.get(media_id_lookup, event.playthrough_id)
            playback_rate = Map.get(play_rate_lookup, event.playthrough_id, 1.0)

            event
            |> Map.put(:media_id, media_id)
            |> Map.put(:position, 0.0)
            |> Map.put(:playback_rate, playback_rate)

          event ->
            event
        end)
      end)

    Playback.record_events(events_data ++ synthetic_events, user_id)

    # 5. Query changes since lastSyncTime and return
    server_time = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    # If no lastSyncTime (initial sync), return all playthroughs and events
    # On subsequent syncs, return only changes since last sync
    {playthroughs, events} =
      if last_sync_time do
        {
          Playback.list_playthroughs_changed_since(user_id, last_sync_time),
          Playback.list_events_changed_since(user_id, last_sync_time)
        }
      else
        {
          Playback.list_all_playthroughs(user_id),
          Playback.list_all_events(user_id)
        }
      end

    # Filter out delete events from the response.
    # Legacy clients don't understand delete events and would crash trying to store them.
    events = Enum.reject(events, &(&1.type == :delete))

    {:ok,
     %{
       playthroughs: playthroughs,
       events: events,
       server_time: server_time
     }}
  end

  # Generates deterministic UUIDs for synthetic events based on playthrough_id.
  # This ensures that syncing the same playthrough multiple times doesn't create
  # duplicate synthetic events (record_events uses on_conflict: :nothing).
  defp deterministic_start_event_id(playthrough_id) do
    deterministic_event_id("start_event", playthrough_id)
  end

  defp deterministic_delete_event_id(playthrough_id) do
    deterministic_event_id("delete_event", playthrough_id)
  end

  defp deterministic_event_id(prefix, playthrough_id) do
    import Bitwise

    hash = :crypto.hash(:sha256, prefix <> ":" <> playthrough_id)
    <<a::32, b::16, c::16, d::16, e::48>> = binary_part(hash, 0, 16)

    # Set UUID version 4 and RFC 4122 variant bits
    c_with_version = (c &&& 0x0FFF) ||| 0x4000
    d_with_variant = (d &&& 0x3FFF) ||| 0x8000

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [
      a,
      b,
      c_with_version,
      d_with_variant,
      e
    ])
    |> IO.iodata_to_binary()
  end

  @doc """
  V2 sync: events only, no playthroughs.

  This is a simplified sync endpoint for clients that have migrated to event-sourced
  playback. All playthrough state is derived from events, so we only need to:
  1. Register/update the device
  2. Record events from client
  3. Return events changed since lastSyncTime

  Unlike sync_progress/2, this does NOT:
  - Accept or sync playthroughs (state is derived from events)
  - Synthesize start/delete events (V2 clients send complete events)
  - Backfill missing fields (V2 clients include all required fields)
  - Filter delete events from response (V2 clients understand them)
  """
  def sync_events(%{input: input}, %{context: %{current_user: %User{id: user_id}}}) do
    %{
      device: device_input,
      events: events_input,
      last_sync_time: last_sync_time
    } = input

    # 1. Register/update device
    device_attrs = Map.put(device_input, :user_id, user_id)
    {:ok, device} = Playback.register_device(device_attrs)

    # 2. Record events from client (with device_id and app info from registered device)
    #    Decode media_id from Relay global ID if present
    events_data =
      Enum.map(events_input, fn event ->
        event
        |> Map.put(:device_id, device.id)
        |> Map.put(:app_version, device.app_version)
        |> Map.put(:app_build, device.app_build)
        |> then(fn event ->
          case event[:media_id] do
            nil ->
              event

            global_id ->
              {:ok, %{id: media_id_str}} = from_global_id(global_id, AmbrySchema)
              Map.put(event, :media_id, String.to_integer(media_id_str))
          end
        end)
      end)

    Playback.record_events(events_data, user_id)

    # 3. Query events changed since lastSyncTime and return (including delete events)
    #    Use V2 query functions that join to playthroughs_new instead of legacy playthroughs
    server_time = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    events =
      if last_sync_time do
        Playback.list_events_changed_since_v2(user_id, last_sync_time)
      else
        Playback.list_all_events_v2(user_id)
      end

    {:ok,
     %{
       events: events,
       server_time: server_time
     }}
  end

  ## Dataloader

  def data, do: Dataloader.Ecto.new(Repo, query: &query/2)

  def query(Media, params) do
    query =
      if params[:allow_all_media] do
        from(m in Media)
      else
        from m in Media, where: m.status == :ready
      end

    apply_params(query, params)
  end

  def query(queryable, params) do
    apply_params(queryable, params)
  end

  defp apply_params(query, %{order: order}), do: from(q in query, order_by: ^order)
  defp apply_params(query, _params), do: query
end
