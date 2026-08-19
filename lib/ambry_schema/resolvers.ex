defmodule AmbrySchema.Resolvers do
  @moduledoc false

  import Absinthe.Relay.Node, only: [from_global_id: 2]
  import Ecto.Query

  alias Ambry.Accounts
  alias Ambry.Accounts.User
  alias Ambry.Books.Book
  alias Ambry.Books.BookUniverse
  alias Ambry.Books.Series
  alias Ambry.Books.SeriesBook
  alias Ambry.Books.Universe
  alias Ambry.Deletions.Deletion
  alias Ambry.Hashids
  alias Ambry.Media.Media
  alias Ambry.Media.MediaNarrator
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.RecordingGroup
  alias Ambry.People.Author
  alias Ambry.People.AuthorPerson
  alias Ambry.People.BookAuthor
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Playback
  alias Ambry.Repo
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

  def people_changed_since(args, _resolution), do: Sync.changes_since(Person, args[:since])
  def authors_changed_since(args, _resolution), do: Sync.changes_since(Author, args[:since])

  def author_people_changed_since(args, _resolution),
    do: Sync.changes_since(AuthorPerson, args[:since])

  def narrators_changed_since(args, _resolution), do: Sync.changes_since(Narrator, args[:since])
  def books_changed_since(args, _resolution), do: Sync.changes_since(Book, args[:since])

  def book_authors_changed_since(args, _resolution),
    do: Sync.changes_since(BookAuthor, args[:since])

  def universes_changed_since(args, _resolution), do: Sync.changes_since(Universe, args[:since])

  def book_universes_changed_since(args, _resolution),
    do: Sync.changes_since(BookUniverse, args[:since])

  def series_changed_since(args, _resolution), do: Sync.changes_since(Series, args[:since])

  def series_books_changed_since(args, _resolution),
    do: Sync.changes_since(SeriesBook, args[:since])

  def media_changed_since(args, _resolution), do: Sync.changes_since(Media, args[:since])

  def media_narrators_changed_since(args, _resolution),
    do: Sync.changes_since(MediaNarrator, args[:since])

  def media_tracks_changed_since(args, _resolution),
    do: Sync.changes_since(MediaTrack, args[:since])

  def recording_groups_changed_since(args, _resolution),
    do: Sync.changes_since(RecordingGroup, args[:since])

  def deletions_since(args, _resolution), do: Sync.deletions_since(args[:since])

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

  def media_track_path(%MediaTrack{} = track, _args, _resolution),
    do: {:ok, MediaTrack.web_path(track)}

  def resolve_decimal(key) do
    fn
      %{^key => nil}, _args, _resolution ->
        {:ok, nil}

      %{^key => value}, _args, _resolution ->
        {:ok, Decimal.to_float(value)}
    end
  end

  def type(%Author{}, _resolution), do: :author
  def type(%AuthorPerson{}, _resolution), do: :author_person
  def type(%Book{}, _resolution), do: :book
  def type(%BookAuthor{}, _resolution), do: :book_author
  def type(%BookUniverse{}, _resolution), do: :book_universe
  def type(%Universe{}, _resolution), do: :universe
  def type(%Deletion{}, _resolution), do: :deletion
  def type(%Media{}, _resolution), do: :media
  def type(%MediaNarrator{}, _resolution), do: :media_narrator
  def type(%MediaTrack{}, _resolution), do: :media_track
  def type(%Narrator{}, _resolution), do: :narrator
  def type(%Person{}, _resolution), do: :person
  def type(%RecordingGroup{}, _resolution), do: :recording_group
  def type(%Series{}, _resolution), do: :series
  def type(%SeriesBook{}, _resolution), do: :series_book

  ## Playback Sync

  @doc """
  V2 sync: events only, no playthroughs.

  This is a simplified sync endpoint for clients that have migrated to event-sourced
  playback. All playthrough state is derived from events, so we only need to:
  1. Register/update the device
  2. Record events from client
  3. Return events changed since lastSyncTime

  All playthrough state is derived from events on both ends.
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
    server_time = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    events =
      if last_sync_time do
        Playback.list_events_changed_since(user_id, last_sync_time)
      else
        Playback.list_all_events(user_id)
      end

    events =
      Enum.map(events, fn event ->
        case event.media_id do
          nil -> event
          id -> %{event | media_id: Absinthe.Relay.Node.to_global_id("Media", id, AmbrySchema)}
        end
      end)

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
