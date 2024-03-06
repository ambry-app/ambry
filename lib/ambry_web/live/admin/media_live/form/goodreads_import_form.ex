defmodule AmbryWeb.Admin.MediaLive.Form.GoodreadsImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Metadata.GoodReads
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

  def handle_event("select-edition", %{"select_edition" => %{"edition_id" => edition_id}}, socket) do
    edition = Enum.find(socket.assigns.editions.editions, &(&1.id == edition_id))
    {:noreply, select_edition(socket, edition)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    book = socket.assigns.edition_details

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
    matching_narrators =
      edition_details
      |> narrators()
      |> Enum.map(fn narrator -> Search.find_first(narrator.name, Person) end)

    assign(socket,
      edition_details_loading: false,
      edition_details: edition_details,
      matching_narrators: matching_narrators
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
      form: to_form(init_import_form_params(socket.assigns.media), as: :import)
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
