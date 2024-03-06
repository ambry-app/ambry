defmodule AmbryWeb.Admin.PersonLive.Form.ImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components

  alias Ambry.Metadata.Audible
  alias Ambry.Metadata.GoodReads

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
          |> async_search(assigns.type, assigns.query)

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
    socket = async_search(socket, socket.assigns.type, query)
    {:noreply, socket}
  end

  def handle_event("select-author", %{"select_author" => %{"author_id" => author_id}}, socket) do
    socket = async_details(socket, socket.assigns.type, author_id)
    {:noreply, socket}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    author = socket.assigns.details

    params =
      Enum.reduce(import_params, %{}, fn
        {"use_name", "true"}, acc ->
          Map.put(acc, "name", author.name)

        {"use_description", "true"}, acc ->
          Map.put(acc, "description", author.description)

        {"use_image", "true"}, acc ->
          Map.merge(acc, %{"image_type" => "url_import", "image_import_url" => author.image.src})

        _else, acc ->
          acc
      end)

    send(self(), {:import, %{"person" => params}})

    {:noreply, socket}
  end

  defp handle_forwarded_info({import_type, :search, {:ok, results}}, socket) do
    socket = assign(socket, search_loading: false, results: results)

    socket =
      case results do
        [] ->
          socket

        [first_result | _rest] ->
          async_details(socket, import_type, first_result.id)
      end

    socket
  end

  defp handle_forwarded_info({_import_type, :search, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "search failed")
    |> assign(search_loading: false)
  end

  defp handle_forwarded_info({_import_type, :details, {:ok, result}}, socket) do
    assign(socket, details_loading: false, details: result)
  end

  defp handle_forwarded_info({_import_type, :details, {:error, _reason}}, socket) do
    socket
    |> put_flash(:error, "fetch failed")
    |> assign(details_loading: false)
  end

  defp async_search(socket, :goodreads, query),
    do: do_async_search(socket, :goodreads, query, &GoodReads.search_authors/1)

  defp async_search(socket, :audible, query),
    do: do_async_search(socket, :audible, query, &Audible.search_authors/1)

  defp do_async_search(socket, import_type, query, query_fun) do
    Task.async(fn ->
      response = query_fun.(query |> String.trim() |> String.downcase())
      {{:for, __MODULE__, socket.assigns.id}, {import_type, :search, response}}
    end)

    assign(socket,
      type: import_type,
      search_form: to_form(%{"query" => query}, as: :search),
      search_loading: true,
      results: [],
      select_author_form: to_form(%{}, as: :select_author),
      details_loading: false,
      details: nil,
      form: to_form(init_import_form_params(socket.assigns.person), as: :import)
    )
  end

  defp async_details(socket, :goodreads, author_id),
    do: do_async_details(socket, :goodreads, author_id, &GoodReads.author/1)

  defp async_details(socket, :audible, author_id),
    do: do_async_details(socket, :audible, author_id, &Audible.author/1)

  defp do_async_details(socket, import_type, author_id, details_fun) do
    Task.async(fn ->
      response = details_fun.(author_id)
      {{:for, __MODULE__, socket.assigns.id}, {import_type, :details, response}}
    end)

    assign(socket,
      select_author_form: to_form(%{"author_id" => author_id}, as: :select_author),
      details_loading: true,
      details: nil
    )
  end

  defp init_import_form_params(person) do
    Map.new([:name, :description, :image], fn
      :name -> {"use_name", is_nil(person.name)}
      :description -> {"use_description", is_nil(person.description)}
      :image -> {"use_image", is_nil(person.image_path)}
    end)
  end

  defp type_title(:goodreads), do: "GoodReads"
  defp type_title(:audible), do: "Audible"
end
