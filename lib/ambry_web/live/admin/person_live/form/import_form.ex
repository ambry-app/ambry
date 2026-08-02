defmodule AmbryWeb.Admin.PersonLive.Form.ImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components

  alias Ambry.Metadata.Providers
  alias Ambry.Provenance
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    %{provider: provider, person: person, query: query} = assigns

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       authors: AsyncResult.loading(),
       selected_author: AsyncResult.loading(),
       refresh: false,
       search_form: to_form(%{"query" => query}, as: :search),
       select_author_form: to_form(%{}, as: :select_author),
       form: to_form(init_import_form_params(person), as: :import)
     )
     |> start_async(:search, fn -> search(provider.id, query) end)}
  end

  @impl Phoenix.LiveComponent
  def handle_async(:search, {:ok, authors}, socket) do
    [first_author | _rest] = authors
    # a Re-fetch search carries its refresh through to the auto-selected
    # author's details fetch — otherwise stale cached details survive
    %{provider: provider, refresh: refresh} = socket.assigns

    {:noreply,
     socket
     |> assign(authors: AsyncResult.ok(socket.assigns.authors, authors), refresh: false)
     |> assign(select_author_form: to_form(%{"author_id" => first_author.id}, as: :select_author))
     |> start_async(:select_author, fn -> select_author(provider.id, first_author, refresh) end)}
  end

  def handle_async(:search, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, authors: AsyncResult.loading())}
  end

  def handle_async(:search, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply,
     assign(socket, authors: AsyncResult.failed(socket.assigns.authors, exception.message))}
  end

  def handle_async(:select_author, {:ok, author}, socket) do
    {:noreply,
     assign(socket,
       selected_author: AsyncResult.ok(socket.assigns.selected_author, author)
     )}
  end

  def handle_async(:select_author, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, assign(socket, selected_author: AsyncResult.loading())}
  end

  def handle_async(:select_author, {:exit, {exception, _stacktrace}}, socket) do
    {:noreply,
     assign(socket,
       selected_author: AsyncResult.failed(socket.assigns.selected_author, exception.message)
     )}
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"search" => %{"query" => query}} = params, socket) do
    %{provider: provider} = socket.assigns
    refresh = Map.has_key?(params, "refresh")

    {:noreply,
     socket
     |> assign(
       authors: AsyncResult.loading(),
       selected_author: AsyncResult.loading(),
       refresh: refresh,
       search_form: to_form(%{"query" => query}, as: :search)
     )
     |> cancel_async(:search)
     |> cancel_async(:select_author)
     |> start_async(:search, fn -> search(provider.id, query, refresh) end)}
  end

  def handle_event("select-author", %{"select_author" => %{"author_id" => author_id}}, socket) do
    author = Enum.find(socket.assigns.authors.result, &(&1.id == author_id))
    %{provider: provider} = socket.assigns

    {:noreply,
     socket
     |> assign(
       selected_author: AsyncResult.loading(),
       select_author_form: to_form(%{"author_id" => author.id}, as: :select_author)
     )
     |> cancel_async(:select_author)
     |> start_async(:select_author, fn -> select_author(provider.id, author) end)}
  end

  def handle_event("import", %{"import" => import_params}, socket) do
    author = socket.assigns.selected_author.result

    params =
      Enum.reduce(import_params, %{}, fn
        {"use_name", "true"}, acc ->
          Map.put(acc, "name", author.name)

        {"use_description", "true"}, acc ->
          Map.put(acc, "description", author.description)

        {"use_image", "true"}, acc ->
          Map.merge(acc, %{
            "image_path" => "",
            "image_type" => "url_import",
            "image_import_url" => author.image_url
          })

        _else, acc ->
          acc
      end)

    source = Provenance.provider_source(socket.assigns.provider.id)
    send(self(), {:import, %{"person" => params}, source})

    {:noreply, socket}
  end

  defp search(provider_id, query, refresh \\ false) do
    "#{query}"
    |> String.trim()
    |> String.downcase()
    |> then(&Providers.search_authors(provider_id, &1, refresh: refresh))
    |> case do
      {:ok, []} -> raise "No authors found"
      {:ok, authors} -> authors
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp select_author(provider_id, author, refresh \\ false) do
    case Providers.author_details(provider_id, author.id, refresh: refresh) do
      {:ok, author} -> author
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp init_import_form_params(person) do
    Map.new([:name, :description, :image], fn
      :name -> {"use_name", is_nil(person.name)}
      :description -> {"use_description", is_nil(person.description)}
      :image -> {"use_image", is_nil(person.image_path)}
    end)
  end
end
