defmodule AmbryWeb.Admin.BookLive.Form.GoodreadsImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Metadata.GoodReads
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
       editions: AsyncResult.loading(),
       edition_details: AsyncResult.loading(),
       search_form: to_form(%{"query" => assigns.query}, as: :search),
       select_book_form: to_form(%{}, as: :select_book),
       select_edition_form: to_form(%{}, as: :select_edition),
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
     |> start_async(:fetch_editions, fn -> fetch_editions(first_book) end)}
  end

  def handle_async(:search, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, books: AsyncResult.loading())}
  end

  def handle_async(:search, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply, assign(socket, books: AsyncResult.failed(socket.assigns.books, exception.message))}
  end

  def handle_async(:fetch_editions, {:ok, editions}, socket) do
    selected_edition =
      Enum.find(editions.editions, List.first(editions.editions), fn edition ->
        edition.format |> String.downcase() |> String.contains?("audio")
      end)

    {:noreply,
     socket
     |> assign(editions: AsyncResult.ok(socket.assigns.editions, editions))
     |> assign(
       select_edition_form: to_form(%{"edition_id" => selected_edition.id}, as: :select_edition)
     )
     |> start_async(:fetch_edition_details, fn -> fetch_edition_details(selected_edition) end)}
  end

  def handle_async(:fetch_editions, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, editions: AsyncResult.loading())}
  end

  def handle_async(:fetch_editions, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply,
     assign(socket, editions: AsyncResult.failed(socket.assigns.editions, exception.message))}
  end

  def handle_async(:fetch_edition_details, {:ok, results}, socket) do
    %{
      edition_details: edition_details,
      matching_authors: matching_authors,
      matching_series: matching_series
    } = results

    {:noreply,
     assign(socket,
       edition_details: AsyncResult.ok(socket.assigns.edition_details, edition_details),
       matching_authors: matching_authors,
       matching_series: matching_series
     )}
  end

  def handle_async(:fetch_edition_details, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, edition_details: AsyncResult.loading())}
  end

  def handle_async(:fetch_edition_details, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply,
     assign(socket,
       edition_details: AsyncResult.failed(socket.assigns.edition_details, exception.message)
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(
       books: AsyncResult.loading(),
       editions: AsyncResult.loading(),
       edition_details: AsyncResult.loading(),
       search_form: to_form(%{"query" => query}, as: :search)
     )
     |> cancel_async(:search)
     |> cancel_async(:fetch_editions)
     |> cancel_async(:fetch_edition_details)
     |> start_async(:search, fn -> search(query) end)}
  end

  def handle_event("select-book", %{"select_book" => %{"book_id" => book_id}}, socket) do
    book = Enum.find(socket.assigns.books.result, &(&1.id == book_id))

    {:noreply,
     socket
     |> assign(
       editions: AsyncResult.loading(),
       edition_details: AsyncResult.loading(),
       select_book_form: to_form(%{"book_id" => book.id}, as: :select_book)
     )
     |> cancel_async(:fetch_editions)
     |> cancel_async(:fetch_edition_details)
     |> start_async(:fetch_editions, fn -> fetch_editions(book) end)}
  end

  def handle_event("select-edition", %{"select_edition" => %{"edition_id" => edition_id}}, socket) do
    edition = Enum.find(socket.assigns.editions.result.editions, &(&1.id == edition_id))

    {:noreply,
     socket
     |> assign(
       edition_details: AsyncResult.loading(),
       select_edition_form: to_form(%{"edition_id" => edition.id}, as: :select_edition)
     )
     |> cancel_async(:fetch_edition_details)
     |> start_async(:fetch_edition_details, fn -> fetch_edition_details(edition) end)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    book = socket.assigns.edition_details.result
    editions = socket.assigns.editions.result

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
          Map.put(
            acc,
            "book_authors",
            build_authors_params(authors(book), socket.assigns.matching_authors)
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
        {:ok, series} = Ambry.Series.create_series(%{name: imported.name})
        %{"book_number" => imported.number, "series_id" => series.id}

      {imported, existing} ->
        %{"book_number" => imported.number, "series_id" => existing.id}
    end)
  end

  defp search(query) do
    case "#{query}" |> String.trim() |> String.downcase() |> GoodReads.search_books() do
      {:ok, []} -> raise "No books found"
      {:ok, books} -> books
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp fetch_editions(book) do
    case GoodReads.editions(book.id) do
      {:ok, %{editions: []}} -> raise "No editions found"
      {:ok, editions} -> editions
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp fetch_edition_details(edition) do
    case GoodReads.edition_details(edition.id) do
      {:ok, edition_details} ->
        matching_authors =
          edition_details
          |> authors()
          |> Enum.map(fn author -> Search.find_first(author.name, Person) end)

        matching_series =
          Enum.map(edition_details.series, fn series ->
            Search.find_first(series.name, Series)
          end)

        %{
          edition_details: edition_details,
          matching_authors: matching_authors,
          matching_series: matching_series
        }

      {:error, reason} ->
        raise "Unhandled error: #{inspect(reason)}"
    end
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
