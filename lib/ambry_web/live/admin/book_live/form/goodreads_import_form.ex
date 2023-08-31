defmodule AmbryWeb.Admin.BookLive.Form.GoodreadsImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Metadata.GoodReads
  alias Ambry.People.Person
  alias Ambry.Search
  alias Ambry.Series.Series

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      case Map.pop(assigns, :info) do
        {nil, assigns} ->
          socket
          |> assign(assigns)
          |> async_search(assigns.query)

        {forwarded_info_payload, assigns} ->
          socket
          |> assign(assigns)
          |> then(fn socket ->
            handle_forwarded_info(forwarded_info_payload, socket)
          end)
      end

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply, async_search(socket, query)}
  end

  def handle_event("select-book", %{"select_book" => %{"book_id" => book_id}}, socket) do
    book = Enum.find(socket.assigns.books, &(&1.id == book_id))
    {:noreply, select_book(socket, book)}
  end

  def handle_event("select-edition", %{"select_edition" => %{"edition_id" => edition_id}}, socket) do
    edition = Enum.find(socket.assigns.editions.editions, &(&1.id == edition_id))
    {:noreply, select_edition(socket, edition)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    book = socket.assigns.edition_details
    editions = socket.assigns.editions

    params =
      Enum.reduce(import_params, %{}, fn
        {"use_title", "true"}, acc ->
          Map.put(acc, "title", book.title)

        {"use_published", "true"}, acc ->
          Map.merge(acc, %{
            "published" => editions.first_published.date,
            "published_format" => editions.first_published.display_format
          })

        {"use_description", "true"}, acc ->
          Map.put(acc, "description", book.description)

        {"use_authors", "true"}, acc ->
          Map.put(acc, "book_authors", build_authors_params(authors(book), socket.assigns.matching_authors))

        {"use_series", "true"}, acc ->
          Map.put(acc, "series_books", build_series_params(book.series, socket.assigns.matching_series))

        {"use_cover_image", "true"}, acc ->
          Map.merge(acc, %{"image_type" => "url_import", "image_import_url" => book.cover_image.src})

        _else, acc ->
          acc
      end)

    send(self(), {:import, %{"book" => params}})

    {:noreply, socket}
  end

  defp build_authors_params(imported_authors, existing_authors) do
    [imported_authors, existing_authors]
    |> Enum.zip()
    |> Enum.flat_map(fn
      {imported, nil} ->
        {:ok, %{authors: [author]}} =
          Ambry.People.create_person(%{name: imported.name, authors: [%{name: imported.name}]})

        [%{"author_id" => author.id}]

      {_imported, %{authors: []} = existing} ->
        {:ok, %{authors: [author]}} = Ambry.People.update_person(existing, %{authors: [%{name: existing.name}]})
        [%{"author_id" => author.id}]

      {_imported, %{authors: [author | _rest]}} ->
        [%{"author_id" => author.id}]
    end)
  end

  defp build_series_params(imported_series, existing_series) do
    [imported_series, existing_series]
    |> Enum.zip()
    |> Enum.map(fn
      {imported, nil} ->
        {:ok, series} = Ambry.Series.create_series(%{name: imported.name})
        %{"book_number" => imported.number, "series_id" => series.id}

      {imported, existing} ->
        %{"book_number" => imported.number, "series_id" => existing.id}
    end)
  end

  defp select_book(socket, book) do
    socket
    |> assign(select_book_form: to_form(%{"book_id" => book.id}, as: :select_book))
    |> async_fetch_editions(book.id)
  end

  defp select_edition(socket, edition) do
    socket
    |> assign(select_edition_form: to_form(%{"edition_id" => edition.id}, as: :select_edition))
    |> async_fetch_edition_details(edition.id)
  end

  defp handle_forwarded_info({:search, {:ok, books}}, socket) do
    socket = assign(socket, search_loading: false, books: books)

    case books do
      [] -> socket
      [first_book | _rest] -> select_book(socket, first_book)
    end
  end

  defp handle_forwarded_info({:search, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "search failed")
    |> assign(search_loading: false)
  end

  defp handle_forwarded_info({:editions, {:ok, editions}}, socket) do
    socket = assign(socket, editions_loading: false, editions: editions)

    selected_edition =
      Enum.find(editions.editions, List.first(editions.editions), fn edition ->
        edition.format |> String.downcase() |> String.contains?("audio")
      end)

    if selected_edition do
      select_edition(socket, selected_edition)
    else
      socket
    end
  end

  defp handle_forwarded_info({:editions, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "fetching editions failed")
    |> assign(editions_loading: false)
  end

  defp handle_forwarded_info({:edition_details, {:ok, edition_details}}, socket) do
    matching_authors =
      edition_details
      |> authors()
      |> Enum.map(fn author -> Search.find_first(author.name, Person) end)

    matching_series =
      Enum.map(edition_details.series, fn series ->
        Search.find_first(series.name, Series)
      end)

    assign(socket,
      edition_details_loading: false,
      edition_details: edition_details,
      matching_authors: matching_authors,
      matching_series: matching_series
    )
  end

  defp handle_forwarded_info({:edition_details, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "fetching edition details failed")
    |> assign(edition_details_loading: false)
  end

  defp async_search(socket, query) do
    Task.async(fn ->
      response = GoodReads.search_books(query |> String.trim() |> String.downcase())
      {{:for, __MODULE__, socket.assigns.id}, {:search, response}}
    end)

    assign(socket,
      search_form: to_form(%{"query" => query}, as: :search),
      search_loading: true,
      books: [],
      select_book_form: to_form(%{}, as: :select_book),
      editions_loading: false,
      editions: nil,
      select_edition_form: to_form(%{}, as: :select_edition),
      edition_details_loading: false,
      edition_details: nil,
      form: to_form(init_import_form_params(socket.assigns.book), as: :import)
    )
  end

  defp async_fetch_editions(socket, book_id) do
    Task.async(fn ->
      response = GoodReads.editions(book_id)
      {{:for, __MODULE__, socket.assigns.id}, {:editions, response}}
    end)

    assign(socket,
      editions_loading: true,
      editions: nil,
      select_edition_form: to_form(%{}, as: :select_edition),
      edition_details: nil
    )
  end

  defp async_fetch_edition_details(socket, edition_id) do
    Task.async(fn ->
      response = GoodReads.edition_details(edition_id)
      {{:for, __MODULE__, socket.assigns.id}, {:edition_details, response}}
    end)

    assign(socket,
      edition_details_loading: true,
      edition_details: nil
    )
  end

  defp init_import_form_params(book) do
    Map.new([:title, :published, :description, :authors, :series, :image], fn
      :title -> {"use_title", is_nil(book.title)}
      :published -> {"use_published", is_nil(book.published)}
      :description -> {"use_description", is_nil(book.description)}
      :authors -> {"use_authors", book.book_authors == []}
      :series -> {"use_series", book.series_books == []}
      :image -> {"use_cover_image", is_nil(book.image_path)}
    end)
  end

  defp authors(edition_details) do
    Enum.filter(edition_details.authors, &(&1.type == "author"))
  end
end