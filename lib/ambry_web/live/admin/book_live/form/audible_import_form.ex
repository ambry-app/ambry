defmodule AmbryWeb.Admin.BookLive.Form.AudibleImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components

  alias Ambry.Metadata.Audible
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
          |> async_import_search(assigns.query)

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
    {:noreply, async_import_search(socket, query)}
  end

  def handle_event("select-book", %{"select_book" => %{"book_id" => book_id}}, socket) do
    book = Enum.find(socket.assigns.results, &(&1.id == book_id))
    {:noreply, select_result(socket, book)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    book = socket.assigns.details

    params =
      Enum.reduce(import_params, %{}, fn
        {"use_title", "true"}, acc ->
          Map.put(acc, "title", book.title)

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
        %{"series_type" => "new", "book_number" => imported.sequence, "series" => %{"name" => imported.title}}

      {imported, existing} ->
        %{"series_type" => "existing", "book_number" => imported.sequence, "series_id" => existing.id}
    end)
  end

  defp handle_forwarded_info({:search, {:ok, results}}, socket) do
    socket = assign(socket, search_loading: false, results: results)

    socket =
      case results do
        [] -> socket
        [first_result | _rest] -> select_result(socket, first_result)
      end

    socket
  end

  defp handle_forwarded_info({:search, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "search failed")
    |> assign(search_loading: false)
  end

  defp async_import_search(socket, query) do
    Task.async(fn ->
      response = Audible.search_books(query |> String.trim() |> String.downcase())
      {{:for, __MODULE__, socket.assigns.id}, {:search, response}}
    end)

    assign(socket,
      search_form: to_form(%{"query" => query}, as: :search),
      search_loading: true,
      results: nil,
      select_book_form: to_form(%{}, as: :select_book),
      details: nil,
      form: to_form(init_import_form_params(socket.assigns.book), as: :import)
    )
  end

  defp init_import_form_params(book) do
    Map.new([:title, :description, :authors, :series, :image], fn
      :title -> {"use_title", is_nil(book.title)}
      :description -> {"use_description", is_nil(book.description)}
      :authors -> {"use_authors", book.book_authors == []}
      :series -> {"use_series", book.series_books == []}
      :image -> {"use_cover_image", is_nil(book.image_path)}
    end)
  end

  defp select_result(socket, result) do
    matching_authors =
      Enum.map(result.authors, fn author ->
        Search.find_first(author.name, Person)
      end)

    matching_series =
      Enum.map(result.series, fn series ->
        Search.find_first(series.title, Series)
      end)

    assign(socket, details: result, matching_authors: matching_authors, matching_series: matching_series)
  end
end
