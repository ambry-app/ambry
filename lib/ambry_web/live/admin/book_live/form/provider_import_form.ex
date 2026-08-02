defmodule AmbryWeb.Admin.BookLive.Form.ProviderImportForm do
  @moduledoc """
  Book import from any registered work-level metadata provider.

  Work-level search results arrive fully hydrated (title, authors, series,
  publication date), so unlike the legacy GoodReads flow there is no
  editions round-trip: search, pick the work, choose fields to import.
  """
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Books
  alias Ambry.Books.Series
  alias Ambry.Metadata.Providers
  alias Ambry.People.Person
  alias Ambry.Provenance
  alias Ambry.Search
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    %{provider: provider, query: query} = assigns

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       books: AsyncResult.loading(),
       selected_book: nil,
       matching_authors: [],
       matching_series: [],
       search_form: to_form(%{"query" => query}, as: :search),
       select_book_form: to_form(%{}, as: :select_book),
       form: to_form(init_import_form_params(assigns.book), as: :import)
     )
     |> start_async(:search, fn -> search(provider.id, query) end)}
  end

  @impl Phoenix.LiveComponent
  def handle_async(:search, {:ok, books}, socket) do
    [first_book | _rest] = books

    {:noreply,
     socket
     |> assign(books: AsyncResult.ok(socket.assigns.books, books))
     |> assign(select_book_form: to_form(%{"book_id" => first_book.id}, as: :select_book))
     |> select_book(first_book)}
  end

  def handle_async(:search, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, books: AsyncResult.loading())}
  end

  def handle_async(:search, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply, assign(socket, books: AsyncResult.failed(socket.assigns.books, exception.message))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"search" => %{"query" => query}} = params, socket) do
    %{provider: provider} = socket.assigns
    refresh = Map.has_key?(params, "refresh")

    {:noreply,
     socket
     |> assign(
       books: AsyncResult.loading(),
       selected_book: nil,
       search_form: to_form(%{"query" => query}, as: :search)
     )
     |> cancel_async(:search)
     |> start_async(:search, fn -> search(provider.id, query, refresh) end)}
  end

  def handle_event("select-book", %{"select_book" => %{"book_id" => book_id}}, socket) do
    book = Enum.find(socket.assigns.books.result, &(&1.id == book_id))

    {:noreply,
     socket
     |> assign(select_book_form: to_form(%{"book_id" => book.id}, as: :select_book))
     |> select_book(book)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    book = socket.assigns.selected_book
    source = Provenance.provider_source(socket.assigns.provider.id)

    params =
      Enum.reduce(import_params, %{}, fn
        {"use_title", "true"}, acc ->
          Map.put(acc, "title", book.title)

        {"use_published", "true"}, acc ->
          Map.merge(acc, %{
            "published" => book.published.date,
            "published_format" => to_string(book.published.display_format)
          })

        {"use_authors", "true"}, acc ->
          Map.put(
            acc,
            "book_authors",
            build_authors_params(socket.assigns.matching_authors, source)
          )

        {"use_series", "true"}, acc ->
          Map.put(acc, "series_books", build_series_params(socket.assigns.matching_series))

        _else, acc ->
          acc
      end)

    send(self(), {:import, %{"book" => params}, source})

    {:noreply, socket}
  end

  defp select_book(socket, book) do
    assign(socket,
      selected_book: book,
      matching_authors:
        Enum.map(book.authors, fn author ->
          {author, Search.find_first(author.name, Person)}
        end),
      matching_series:
        Enum.map(book.series, fn series ->
          {series, Search.find_first(series.name, Series)}
        end)
    )
  end

  defp build_authors_params(matching_authors, source) do
    Enum.map(matching_authors, fn
      {imported, nil} ->
        {:ok, %{author_people: [%{author: author}]}} =
          Ambry.People.create_person(
            %{
              name: imported.name,
              author_people: [%{author: %{name: imported.name}}]
            },
            provenance: %{"name" => source}
          )

        %{"author_id" => author.id}

      {_imported, %{authors: []} = existing} ->
        {:ok, %{author_people: [%{author: author}]}} =
          Ambry.People.update_person(existing, %{
            author_people: [%{author: %{name: existing.name}}]
          })

        %{"author_id" => author.id}

      {_imported, %{authors: [author | _rest]}} ->
        %{"author_id" => author.id}
    end)
  end

  defp build_series_params(matching_series) do
    Enum.map(matching_series, fn
      {imported, nil} ->
        {:ok, series} = Books.create_series(%{name: imported.name})
        %{"book_number" => imported.number, "series_id" => series.id}

      {imported, existing} ->
        %{"book_number" => imported.number, "series_id" => existing.id}
    end)
  end

  defp search(provider_id, query, refresh \\ false) do
    "#{query}"
    |> String.trim()
    |> String.downcase()
    |> then(&Providers.search_books(provider_id, &1, refresh: refresh))
    |> case do
      {:ok, []} -> raise "No books found"
      {:ok, books} -> books
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp init_import_form_params(book) do
    Map.new([:title, :published, :authors, :series], fn
      :title -> {"use_title", is_nil(book.title)}
      :published -> {"use_published", is_nil(book.published)}
      :authors -> {"use_authors", book.book_authors == []}
      :series -> {"use_series", book.series_books == []}
    end)
  end
end
