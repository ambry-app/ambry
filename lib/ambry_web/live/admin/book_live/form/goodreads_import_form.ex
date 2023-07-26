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
          Map.put(acc, "book_authors", build_authors_params(book.authors, socket.assigns.matching_authors))

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
      {_imported, nil} -> []
      {_imported, existing} -> [%{"author_id" => existing.id}]
    end)
  end

  defp build_series_params(imported_series, existing_series) do
    [imported_series, existing_series]
    |> Enum.zip()
    |> Enum.map(fn
      {imported, nil} ->
        %{"series_type" => "new", "book_number" => imported.number, "series" => %{"name" => imported.name}}

      {imported, existing} ->
        %{"series_type" => "existing", "book_number" => imported.number, "series_id" => existing.id}
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
      Enum.flat_map(edition_details.authors, fn
        %{type: "author"} = author -> [Search.find_first(author.name, Person)]
        _other -> []
      end)

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

  # Components

  attr :book, :any, required: true
  slot :actions

  defp book_card(%{book: %AmbryScraping.GoodReads.Books.Search.Book{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.thumbnail.data_url} class="object-contain object-top" />
      <div>
        <p class="font-bold"><%= @book.title %></p>
        <p class="text-zinc-400">
          by
          <span :for={contributor <- @book.contributors} class="group">
            <span><%= contributor.name %></span>
            <span class="text-xs text-zinc-600">(<%= contributor.type %>)</span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <div :for={action <- @actions}>
          <%= render_slot(action) %>
        </div>
      </div>
    </div>
    """
  end

  defp book_card(%{book: %AmbryScraping.GoodReads.Books.Editions.Edition{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.thumbnail.data_url} class="object-contain object-top" />
      <div>
        <p class="font-bold"><%= @book.title %></p>
        <p class="text-zinc-400">
          by
          <span :for={contributor <- @book.contributors} class="group">
            <span><%= contributor.name %></span>
            <span class="text-xs text-zinc-600">(<%= contributor.type %>)</span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <p :if={@book.published && @book.publisher} class="text-xs text-zinc-400">
          Published <%= display_date(@book.published) %> by <%= @book.publisher %>
        </p>
        <p class="text-xs text-zinc-400"><%= @book.format %></p>
        <div :for={action <- @actions}>
          <%= render_slot(action) %>
        </div>
      </div>
    </div>
    """
  end

  defp display_date(%Date{} = date), do: Calendar.strftime(date, "%B %-d, %Y")

  defp display_date(%AmbryScraping.GoodReads.PublishedDate{display_format: :full, date: date}),
    do: Calendar.strftime(date, "%B %-d, %Y")

  defp display_date(%AmbryScraping.GoodReads.PublishedDate{display_format: :year_month, date: date}),
    do: Calendar.strftime(date, "%B %Y")

  defp display_date(%AmbryScraping.GoodReads.PublishedDate{display_format: :year, date: date}),
    do: Calendar.strftime(date, "%Y")
end
