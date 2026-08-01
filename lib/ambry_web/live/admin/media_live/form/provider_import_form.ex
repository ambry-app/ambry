defmodule AmbryWeb.Admin.MediaLive.Form.ProviderImportForm do
  @moduledoc """
  Media (recording) import from any registered recording-level metadata
  provider — narrators, square cover art, publisher, and publication facts.
  """
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.Components.RichSelect, only: [rich_select: 1]

  alias Ambry.Metadata.Providers
  alias Ambry.People.Person
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
       matching_narrators: [],
       search_form: to_form(%{"query" => query}, as: :search),
       select_book_form: to_form(%{}, as: :select_book),
       form: to_form(init_import_form_params(assigns.media), as: :import)
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

    params =
      Enum.reduce(import_params, %{}, fn
        {"use_published", "true"}, acc ->
          Map.merge(acc, %{
            "published" => book.published.date,
            "published_format" => to_string(book.published.display_format)
          })

        {"use_publisher", "true"}, acc ->
          Map.put(acc, "publisher", book.publisher)

        {"use_description", "true"}, acc ->
          Map.put(acc, "description", book.description)

        {"use_narrators", "true"}, acc ->
          Map.put(
            acc,
            "media_narrators",
            build_narrators_params(socket.assigns.matching_narrators)
          )

        {"use_cover_image", "true"}, acc ->
          Map.merge(acc, %{
            "image_path" => "",
            "image_type" => "url_import",
            "image_import_url" => book.cover_url
          })

        _else, acc ->
          acc
      end)

    send(self(), {:import, %{"media" => params}})

    {:noreply, socket}
  end

  defp select_book(socket, book) do
    assign(socket,
      selected_book: book,
      matching_narrators:
        Enum.map(book.narrators, fn narrator ->
          {narrator, Search.find_first(narrator.name, Person)}
        end)
    )
  end

  defp build_narrators_params(matching_narrators) do
    Enum.map(matching_narrators, fn
      {imported, nil} ->
        {:ok, %{narrators: [narrator]}} =
          Ambry.People.create_person(%{name: imported.name, narrators: [%{name: imported.name}]})

        %{"narrator_id" => narrator.id}

      {_imported, %{narrators: []} = existing} ->
        {:ok, %{narrators: [narrator]}} =
          Ambry.People.update_person(existing, %{narrators: [%{name: existing.name}]})

        %{"narrator_id" => narrator.id}

      {_imported, %{narrators: [narrator | _rest]}} ->
        %{"narrator_id" => narrator.id}
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

  defp init_import_form_params(media) do
    Map.new([:published, :publisher, :description, :narrators, :image], fn
      :published -> {"use_published", is_nil(media.published)}
      :publisher -> {"use_publisher", is_nil(media.publisher)}
      :description -> {"use_description", is_nil(media.description)}
      :narrators -> {"use_narrators", media.media_narrators == []}
      :image -> {"use_cover_image", is_nil(media.image_path)}
    end)
  end
end
