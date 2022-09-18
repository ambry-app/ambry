defmodule AmbrySchema.Resolvers do
  @moduledoc false

  import Absinthe.Relay.Node, only: [from_global_id: 2]
  import Absinthe.Resolution.Helpers, only: [batch: 3]
  import Ecto.Query

  alias Absinthe.Relay.Connection

  alias Ambry.{Accounts, Repo}

  alias Ambry.Accounts.User
  alias Ambry.Authors.Author
  alias Ambry.Books.Book
  alias Ambry.Media.{Media, PlayerState}
  alias Ambry.Narrators.Narrator
  alias Ambry.People.Person
  alias Ambry.{Repo, Search}
  alias Ambry.Series.{Series, SeriesBook}

  alias AmbryWeb.Hashids

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
    user_token && Accounts.delete_session_token(user_token)

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
    narrator
    |> Ecto.assoc(:media)
    |> join(:inner, [m], b in assoc(m, :book))
    |> order_by([_, _, b], desc: b.published)
    |> Connection.from_query(&Repo.all/1, args)
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

  def update_player_state(%{media_id: media_id} = args, %{
        context: %{current_user: %User{} = user}
      }) do
    with {:ok, %{id: media_id, type: :media}} <- from_global_id(media_id, AmbrySchema),
         player_state = Ambry.Media.get_or_create_player_state!(user.id, media_id),
         attrs = Map.delete(args, :media_id),
         {:ok, player_state} <- Ambry.Media.update_player_state(player_state, attrs) do
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
    fn %{^key => value}, _args, _resolution ->
      {:ok, Decimal.to_float(value)}
    end
  end

  def node(%{type: :author, id: id}, _resolution), do: {:ok, Repo.get(Author, id)}
  def node(%{type: :book, id: id}, _resolution), do: {:ok, Repo.get(Book, id)}
  def node(%{type: :media, id: id}, _resolution), do: {:ok, Repo.get(Media, id)}
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
  def type(%Media{}, _resolution), do: :media
  def type(%Narrator{}, _resolution), do: :narrator
  def type(%Person{}, _resolution), do: :person
  def type(%PlayerState{}, _resolution), do: :player_state
  def type(%Series{}, _resolution), do: :series
  def type(%SeriesBook{}, _resolution), do: :series_book

  # Custom batches

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

  # Dataloader

  def data, do: Dataloader.Ecto.new(Repo, query: &query/2)

  def query(queryable, params), do: queryable |> query_for() |> apply_params(params)

  defp query_for(Media), do: from(m in Media, where: m.status == :ready)
  defp query_for(queryable), do: queryable

  defp apply_params(query, %{order: order}), do: from(q in query, order_by: ^order)
  defp apply_params(query, _params), do: query
end
