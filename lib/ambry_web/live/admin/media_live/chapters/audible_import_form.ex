defmodule AmbryWeb.Admin.MediaLive.Chapters.AudibleImportForm do
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
    chapters = socket.assigns.chapters

    import_type =
      cond do
        Map.has_key?(import_params, "titles_only") -> :titles_only
        Map.has_key?(import_params, "times_only") -> :times_only
        true -> :all
      end

    params =
      if import_params["use_chapters"] == "true" do
        %{"chapters" => build_chapters_params(chapters.chapters, import_type)}
      else
        %{}
      end

    send(self(), {:import, %{"media" => params}})

    {:noreply, socket}
  end

  defp build_chapters_params(chapters, import_type) do
    Enum.map(chapters, &build_chapter_params(&1, import_type))
  end

  defp build_chapter_params(chapter, :titles_only), do: %{"title" => chapter.title}
  defp build_chapter_params(chapter, :times_only), do: %{"time" => time(chapter)}

  defp build_chapter_params(chapter, :all),
    do: %{"title" => chapter.title, "time" => time(chapter)}

  defp time(chapter),
    do: chapter.start_offset_ms |> Decimal.new() |> Decimal.div(1000) |> Decimal.round(2)

  defp select_book(socket, book) do
    matching_narrators =
      Enum.map(book.narrators, fn narrator -> Search.find_first(narrator.name, Person) end)

    socket
    |> assign(
      selected_book: book,
      matching_narrators: matching_narrators,
      select_book_form: to_form(%{"book_id" => book.id}, as: :select_book)
    )
    |> async_fetch_chapters(book.id)
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

  defp handle_forwarded_info({:chapters, {:ok, chapters}}, socket) do
    assign(socket, chapters_loading: false, chapters: chapters)
  end

  defp handle_forwarded_info({:chapters, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "fetching chapters failed")
    |> assign(chapters_loading: false)
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
      chapters_loading: false,
      chapters: nil,
      form: to_form(init_import_form_params(socket.assigns.media), as: :import)
    )
  end

  defp async_fetch_chapters(socket, id) do
    Task.async(fn ->
      response = Audible.chapters(id)
      {{:for, __MODULE__, socket.assigns.id}, {:chapters, response}}
    end)

    assign(socket,
      chapters_loading: true,
      chapters: nil
    )
  end

  defp init_import_form_params(media) do
    Map.new([:chapters], fn
      :chapters -> {"use_chapters", media.chapters == []}
    end)
  end
end
