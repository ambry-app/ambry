defmodule AmbryWeb.Admin.MediaLive.Form.AudibleImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Metadata.Audible
  alias Ambry.People.Person
  alias Ambry.Search

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

  def handle_event("import", %{"import" => import_params}, socket) do
    book = socket.assigns.selected_book

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

  defp select_book(socket, book) do
    matching_narrators =
      Enum.map(book.narrators, fn narrator -> Search.find_first(narrator.name, Person) end)

    assign(socket,
      selected_book: book,
      matching_narrators: matching_narrators,
      select_book_form: to_form(%{"book_id" => book.id}, as: :select_book)
    )
  end

  defp handle_forwarded_info({:search, {:ok, books}}, socket) do
    socket = assign(socket, search_loading: false, books: books)

    case books do
      [] -> socket
      [first_result | _rest] -> select_book(socket, first_result)
    end
  end

  defp handle_forwarded_info({:search, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "search failed")
    |> assign(search_loading: false)
  end

  defp async_search(socket, query) do
    Task.async(fn ->
      response = Audible.search_books(query |> String.trim() |> String.downcase())
      {{:for, __MODULE__, socket.assigns.id}, {:search, response}}
    end)

    assign(socket,
      search_form: to_form(%{"query" => query}, as: :search),
      search_loading: true,
      books: [],
      select_book_form: to_form(%{}, as: :select_book),
      selected_book: nil,
      form: to_form(init_import_form_params(socket.assigns.media), as: :import)
    )
  end

  defp init_import_form_params(media) do
    Map.new([:published, :narrators], fn
      :published -> {"use_published", is_nil(media.published)}
      :narrators -> {"use_narrators", media.media_narrators == []}
    end)
  end
end
