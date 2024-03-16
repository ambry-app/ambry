defmodule AmbryWeb.Admin.MediaLive.Form.AudibleImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Metadata.Audible
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
       selected_book: AsyncResult.loading(),
       search_form: to_form(%{"query" => assigns.query}, as: :search),
       select_book_form: to_form(%{}, as: :select_book),
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
      matching_narrators: matching_narrators
    } = results

    {:noreply,
     assign(socket,
       selected_book: AsyncResult.ok(socket.assigns.selected_book, selected_book),
       matching_narrators: matching_narrators
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
        {"use_published", "true"}, acc ->
          Map.merge(acc, %{
            "published" => book.published,
            "published_format" => "full"
          })

        {"use_narrators", "true"}, acc ->
          Map.put(
            acc,
            "media_narrators",
            build_narrators_params(book.narrators, socket.assigns.matching_narrators)
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
    case "#{query}" |> String.trim() |> String.downcase() |> Audible.search_books() do
      {:ok, []} -> raise "No books found"
      {:ok, books} -> books
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp select_book(book) do
    matching_narrators =
      Enum.map(book.narrators, fn author ->
        Search.find_first(author.name, Person)
      end)

    %{selected_book: book, matching_narrators: matching_narrators}
  end

  defp init_import_form_params(media) do
    Map.new([:published, :narrators], fn
      :published -> {"use_published", is_nil(media.published)}
      :narrators -> {"use_narrators", media.media_narrators == []}
    end)
  end
end
