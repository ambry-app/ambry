defmodule AmbryWeb.Admin.MediaLive.Chapters.AudibleImportForm do
  @moduledoc """
  Chapter **titles** from Audible: catalog search for the recording, Audnexus
  for its chapter list (keyed by ASIN).

  It used to import the list wholesale, timestamps and all, which is the one
  thing 1h says must never happen. Audible's chapter times describe Audible's
  retail edition; a rip is a different encode, so the offsets start seconds
  off and the error compounds — the chapters most likely to land in the wrong
  place are the ones a reader reaches last. That is inherent to the data and
  not fixable by being careful.

  So the times that arrive here are read for exactly one purpose: to compute
  the *durations* between them, which are local and therefore drift-immune,
  and align the two lists. Then they're thrown away and only the titles land.
  See `Ambry.Media.Chapters.Merge`.
  """
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]
  import AmbryWeb.Admin.MediaLive.Chapters.Preview

  alias Ambry.Media.Chapters.Merge
  alias Ambry.Metadata.Providers
  alias Phoenix.LiveView.AsyncResult

  @search_provider "audible"
  @chapters_provider "audnexus"

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
       refresh: false,
       search_form: to_form(%{"query" => assigns.query}, as: :search),
       select_book_form: to_form(%{}, as: :select_book)
     )
     |> start_async(:search, fn -> search(assigns.query) end)}
  end

  @impl Phoenix.LiveComponent
  def handle_async(:search, {:ok, books}, socket) do
    [first_book | _rest] = books
    # a Re-fetch search carries its refresh through to the chained
    # chapters fetch — otherwise stale cached chapters survive
    refresh = socket.assigns.refresh

    {:noreply,
     socket
     |> assign(books: AsyncResult.ok(socket.assigns.books, books), refresh: false)
     |> assign(select_book_form: to_form(%{"book_id" => first_book.id}, as: :select_book))
     |> start_async(:fetch_chapters, fn -> fetch_chapters(first_book, refresh) end)}
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
  def handle_event("search", %{"search" => %{"query" => query}} = params, socket) do
    refresh = Map.has_key?(params, "refresh")

    {:noreply,
     socket
     |> assign(
       books: AsyncResult.loading(),
       chapters: AsyncResult.loading(),
       refresh: refresh,
       search_form: to_form(%{"query" => query}, as: :search)
     )
     |> cancel_async(:search)
     |> cancel_async(:fetch_chapters)
     |> start_async(:search, fn -> search(query, refresh) end)}
  end

  def handle_event("select-book", %{"select_book" => %{"book_id" => book_id}}, socket) do
    book = Enum.find(socket.assigns.books.result, &(&1.id == book_id))

    {:noreply,
     socket
     |> assign(select_book_form: to_form(%{"book_id" => book.id}, as: :select_book))
     |> cancel_async(:fetch_chapters)
     |> start_async(:fetch_chapters, fn -> fetch_chapters(book) end)}
  end

  def handle_event("import", _params, socket) do
    {merged, _alignment} =
      Merge.titles(socket.assigns.markers, incoming(socket.assigns.chapters.result), :provider)

    # No marker source: a titles merge changed no marker, and claiming
    # otherwise would put a provider's name on a timeline it never touched.
    send(self(), {:chapters, merged, nil})

    {:noreply, socket}
  end

  # Audnexus reports milliseconds from the start of its own edition. They
  # exist here only so the alignment has durations to compare.
  defp incoming(%{chapters: chapters}) do
    Enum.map(chapters, fn chapter ->
      %{title: chapter.title, time: time(chapter)}
    end)
  end

  defp preview_incoming(result), do: incoming(result)

  defp preview_alignment(markers, result), do: Merge.align(markers, incoming(result))

  defp preview_summary(markers, result),
    do: markers |> Merge.align(incoming(result)) |> Merge.summarize()

  defp time(chapter),
    do: chapter.start_offset_ms |> Decimal.new() |> Decimal.div(1000) |> Decimal.round(2)

  defp search(query, refresh \\ false) do
    "#{query}"
    |> String.trim()
    |> String.downcase()
    |> then(&Providers.search_books(@search_provider, &1, refresh: refresh))
    |> case do
      {:ok, []} -> raise "No books found"
      {:ok, books} -> books
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp fetch_chapters(book, refresh \\ false) do
    case Providers.chapters(@chapters_provider, book.asin, refresh: refresh) do
      {:ok, chapters} -> chapters
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end
end
