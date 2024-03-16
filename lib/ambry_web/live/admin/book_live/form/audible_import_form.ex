defmodule AmbryWeb.Admin.BookLive.Form.AudibleImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Metadata.Audible
  alias Ambry.People.Person
  alias Ambry.Search
  alias Ambry.Series.Series
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       books: AsyncResult.loading(),
       selected_book: AsyncResult.loading(),
       search_form: to_form(%{"query" => assigns.query}, as: :search),
       select_book_form: to_form(%{}, as: :select_book),
       form: to_form(init_import_form_params(assigns.book), as: :import)
     )
     |> start_async(:search, fn -> search(assigns.query) end)}
  end

  @impl Phoenix.LiveComponent
  def handle_async(:search, {:ok, books}, socket) do
    [first_book | _rest] = books

    {:noreply,
     socket
     |> assign(books: AsyncResult.ok(socket.assigns.books, books))
     |> assign(select_book_form: to_form(%{"book_id" => first_book.id}, as: :select_book))
     |> start_async(:select_book, fn -> select_book(first_book) end)}
  end

  def handle_async(:search, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, books: AsyncResult.loading())}
  end

  def handle_async(:search, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply, assign(socket, books: AsyncResult.failed(socket.assigns.books, exception.message))}
  end

  def handle_async(:select_book, {:ok, results}, socket) do
    %{
      selected_book: selected_book,
      matching_authors: matching_authors,
      matching_series: matching_series
    } = results

    {:noreply,
     assign(socket,
       selected_book: AsyncResult.ok(socket.assigns.selected_book, selected_book),
       matching_authors: matching_authors,
       matching_series: matching_series
     )}
  end

  def handle_async(:select_book, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, selected_book: AsyncResult.loading())}
  end

  def handle_async(:select_book, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply,
     assign(socket,
       selected_book: AsyncResult.failed(socket.assigns.selected_book, exception.message)
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(
       books: AsyncResult.loading(),
       selected_book: AsyncResult.loading(),
       search_form: to_form(%{"query" => query}, as: :search)
     )
     |> cancel_async(:search)
     |> cancel_async(:select_book)
     |> start_async(:search, fn -> search(query) end)}
  end

  def handle_event("select-book", %{"select_book" => %{"book_id" => book_id}}, socket) do
    book = Enum.find(socket.assigns.books.result, &(&1.id == book_id))

    {:noreply,
     socket
     |> assign(
       selected_book: AsyncResult.loading(),
       select_book_form: to_form(%{"book_id" => book.id}, as: :select_book)
     )
     |> cancel_async(:select_book)
     |> start_async(:select_book, fn -> select_book(book) end)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    book = socket.assigns.selected_book.result

    params =
      Enum.reduce(import_params, %{}, fn
        {"use_title", "true"}, acc ->
          Map.put(acc, "title", book.title)

        {"use_description", "true"}, acc ->
          Map.put(acc, "description", book.description)

        {"use_authors", "true"}, acc ->
          Map.put(
            acc,
            "book_authors",
            build_authors_params(book.authors, socket.assigns.matching_authors)
          )

        {"use_series", "true"}, acc ->
          Map.put(
            acc,
            "series_books",
            build_series_params(book.series, socket.assigns.matching_series)
          )

        {"use_cover_image", "true"}, acc ->
          Map.merge(acc, %{
            "image_type" => "url_import",
            "image_import_url" => book.cover_image.src
          })

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
        {:ok, %{authors: [author]}} =
          Ambry.People.update_person(existing, %{authors: [%{name: existing.name}]})

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
        {:ok, series} = Ambry.Series.create_series(%{name: imported.title})
        %{"book_number" => imported.sequence, "series_id" => series.id}

      {imported, existing} ->
        %{"book_number" => imported.sequence, "series_id" => existing.id}
    end)
  end

  defp search(query) do
    case "#{query}" |> String.trim() |> String.downcase() |> Audible.search_books() do
      {:ok, []} -> raise "No books found"
      {:ok, books} -> books
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp select_book(book) do
    matching_authors =
      Enum.map(book.authors, fn author ->
        Search.find_first(author.name, Person)
      end)

    matching_series =
      Enum.map(book.series, fn series ->
        Search.find_first(series.title, Series)
      end)

    %{selected_book: book, matching_authors: matching_authors, matching_series: matching_series}
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
end
