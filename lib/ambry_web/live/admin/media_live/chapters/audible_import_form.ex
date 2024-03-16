defmodule AmbryWeb.Admin.MediaLive.Chapters.AudibleImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Metadata.Audible
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
       chapters: AsyncResult.loading(),
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
     |> start_async(:fetch_chapters, fn -> fetch_chapters(first_book) end)}
  end

  def handle_async(:search, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, books: AsyncResult.loading())}
  end

  def handle_async(:search, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply, assign(socket, books: AsyncResult.failed(socket.assigns.books, exception.message))}
  end

  def handle_async(:fetch_chapters, {:ok, chapters}, socket) do
    {:noreply, assign(socket, chapters: AsyncResult.ok(socket.assigns.chapters, chapters))}
  end

  def handle_async(:fetch_chapters, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, chapters: AsyncResult.loading())}
  end

  def handle_async(:fetch_chapters, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply,
     assign(socket,
       chapters: AsyncResult.failed(socket.assigns.chapters, exception.message)
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(
       books: AsyncResult.loading(),
       chapters: AsyncResult.loading(),
       search_form: to_form(%{"query" => query}, as: :search)
     )
     |> cancel_async(:search)
     |> cancel_async(:fetch_chapters)
     |> start_async(:search, fn -> search(query) end)}
  end

  def handle_event("select-book", %{"select_book" => %{"book_id" => book_id}}, socket) do
    book = Enum.find(socket.assigns.books.result, &(&1.id == book_id))

    {:noreply,
     socket
     |> assign(select_book_form: to_form(%{"book_id" => book.id}, as: :select_book))
     |> cancel_async(:fetch_chapters)
     |> start_async(:fetch_chapters, fn -> fetch_chapters(book) end)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    chapters = socket.assigns.chapters.result

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

  defp search(query) do
    case "#{query}" |> String.trim() |> String.downcase() |> Audible.search_books() do
      {:ok, []} -> raise "No books found"
      {:ok, books} -> books
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp fetch_chapters(book) do
    case Audible.chapters(book.id) do
      {:ok, chapters} -> chapters
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp init_import_form_params(media) do
    Map.new([:chapters], fn
      :chapters -> {"use_chapters", media.chapters == []}
    end)
  end
end
