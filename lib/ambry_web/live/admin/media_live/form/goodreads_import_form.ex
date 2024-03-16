defmodule AmbryWeb.Admin.MediaLive.Form.GoodreadsImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Metadata.GoodReads
  alias Ambry.People.Person
  alias Ambry.Search
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
       form: to_form(init_import_form_params(assigns.media), as: :import)
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
      matching_narrators: matching_narrators
    } = results

    {:noreply,
     assign(socket,
       edition_details: AsyncResult.ok(socket.assigns.edition_details, edition_details),
       matching_narrators: matching_narrators
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

    params =
      Enum.reduce(import_params, %{}, fn
        {"use_published", "true"}, acc ->
          Map.merge(acc, %{
            "published" => book.published.date,
            "published_format" => book.published.display_format
          })

        {"use_narrators", "true"}, acc ->
          Map.put(
            acc,
            "media_narrators",
            build_narrators_params(narrators(book), socket.assigns.matching_narrators)
          )

        _else, acc ->
          acc
      end)

    send(self(), {:import, %{"media" => params}})

    {:noreply, socket}
  end

  defp build_narrators_params(imported_narrators, existing_narrators) do
    [imported_narrators, existing_narrators]
    |> Enum.zip()
    |> Enum.flat_map(fn
      {imported, nil} ->
        {:ok, %{narrators: [narrator]}} =
          Ambry.People.create_person(%{name: imported.name, narrators: [%{name: imported.name}]})

        [%{"narrator_id" => narrator.id}]

      {_imported, %{narrators: []} = existing} ->
        {:ok, %{narrators: [narrator]}} =
          Ambry.People.update_person(existing, %{narrators: [%{name: existing.name}]})

        [%{"narrator_id" => narrator.id}]

      {_imported, %{narrators: [narrator | _rest]}} ->
        [%{"narrator_id" => narrator.id}]
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
        matching_narrators =
          edition_details
          |> narrators()
          |> Enum.map(fn narrator -> Search.find_first(narrator.name, Person) end)

        %{
          edition_details: edition_details,
          matching_narrators: matching_narrators
        }

      {:error, reason} ->
        raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp init_import_form_params(media) do
    Map.new([:published, :narrators], fn
      :published -> {"use_published", is_nil(media.published)}
      :narrators -> {"use_narrators", media.media_narrators == []}
    end)
  end

  defp narrators(edition_details) do
    Enum.filter(edition_details.authors, &(&1.type in ["narrator", "read by", "reader"]))
  end
end
