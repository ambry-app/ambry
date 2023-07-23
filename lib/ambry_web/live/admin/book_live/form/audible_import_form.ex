defmodule AmbryWeb.Admin.BookLive.Form.AudibleImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components

  alias Ambry.Metadata.Audible

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
          |> async_import_search(assigns.query)

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
    {:noreply, async_import_search(socket, query)}
  end

  def handle_event("select-book", %{"select_book" => %{"book_id" => book_id}}, socket) do
    book = Enum.find(socket.assigns.results, &(&1.id == book_id))
    {:noreply, assign(socket, details: book)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    book = socket.assigns.details

    params =
      Enum.reduce(import_params, %{}, fn
        {"use_title", "true"}, acc ->
          Map.put(acc, "title", book.title)

        {"use_description", "true"}, acc ->
          Map.put(acc, "description", book.description)

        {"use_cover_image", "true"}, acc ->
          Map.merge(acc, %{"image_type" => "url_import", "image_import_url" => book.cover_image.src})

        _else, acc ->
          acc
      end)

    send(self(), {:import, %{"book" => params}})

    {:noreply, socket}
  end

  defp handle_forwarded_info({:search, {:ok, results}}, socket) do
    socket = assign(socket, search_loading: false, results: results)

    socket =
      case results do
        [] -> socket
        [first_result | _rest] -> assign(socket, details: first_result)
      end

    socket
  end

  defp handle_forwarded_info({:search, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "search failed")
    |> assign(search_loading: false)
  end

  defp async_import_search(socket, query) do
    Task.async(fn ->
      response = Audible.search_books(query |> String.trim() |> String.downcase())
      {{:for, __MODULE__, socket.assigns.id}, {:search, response}}
    end)

    assign(socket,
      search_form: to_form(%{"query" => query}, as: :search),
      search_loading: true,
      results: nil,
      select_book_form: to_form(%{}, as: :select_book),
      details: nil,
      form: to_form(init_import_form_params(socket.assigns.book), as: :import)
    )
  end

  defp init_import_form_params(book) do
    Map.new([:title, :description, :image], fn
      :title -> {"use_title", is_nil(book.title)}
      :description -> {"use_description", is_nil(book.description)}
      :image -> {"use_cover_image", is_nil(book.image_path)}
    end)
  end
end
