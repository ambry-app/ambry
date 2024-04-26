defmodule AmbryWeb.Admin.PersonLive.Form.ImportForm do
  @moduledoc false
  use AmbryWeb, :live_component

  import AmbryWeb.Admin.Components

  alias Ambry.Metadata.Audible
  alias Ambry.Metadata.GoodReads
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    %{type: type, person: person, query: query} = assigns

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       authors: AsyncResult.loading(),
       selected_author: AsyncResult.loading(),
       search_form: to_form(%{"query" => query}, as: :search),
       select_author_form: to_form(%{}, as: :select_author),
       form: to_form(init_import_form_params(person), as: :import)
     )
     |> start_async(:search, fn -> search(type, query) end)}
  end

  @impl Phoenix.LiveComponent
  def handle_async(:search, {:ok, authors}, socket) do
    [first_author | _rest] = authors
    %{type: type} = socket.assigns

    {:noreply,
     socket
     |> assign(authors: AsyncResult.ok(socket.assigns.authors, authors))
     |> assign(select_author_form: to_form(%{"author_id" => first_author.id}, as: :select_author))
     |> start_async(:select_author, fn -> select_author(type, first_author) end)}
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
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    %{type: type} = socket.assigns

    {:noreply,
     socket
     |> assign(
       books: AsyncResult.loading(),
       selected_book: AsyncResult.loading(),
       search_form: to_form(%{"query" => query}, as: :search)
     )
     |> cancel_async(:search)
     |> cancel_async(:select_book)
     |> start_async(:search, fn -> search(type, query) end)}
  end

  def handle_event("select-author", %{"select_author" => %{"author_id" => author_id}}, socket) do
    author = Enum.find(socket.assigns.authors.result, &(&1.id == author_id))
    %{type: type} = socket.assigns

    {:noreply,
     socket
     |> assign(
       selected_author: AsyncResult.loading(),
       select_author_form: to_form(%{"author_id" => author.id}, as: :select_author)
     )
     |> cancel_async(:select_author)
     |> start_async(:select_author, fn -> select_author(type, author) end)}
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
            "image_import_url" => author.image
          })

        _else, acc ->
          acc
      end)

    send(self(), {:import, %{"person" => params}})

    {:noreply, socket}
  end

  defp search(:goodreads, query), do: do_search(query, &GoodReads.search_authors/1)
  defp search(:audible, query), do: do_search(query, &Audible.search_authors/1)

  defp do_search(query, query_fun) do
    case "#{query}" |> String.trim() |> String.downcase() |> query_fun.() do
      {:ok, []} -> raise "No authors found"
      {:ok, authors} -> authors
      {:error, reason} -> raise "Unhandled error: #{inspect(reason)}"
    end
  end

  defp select_author(:goodreads, author), do: do_select_author(author, &GoodReads.author/1)
  defp select_author(:audible, author), do: do_select_author(author, &Audible.author/1)

  defp do_select_author(author, author_fun) do
    case author_fun.(author.id) do
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

  defp type_title(:goodreads), do: "GoodReads"
  defp type_title(:audible), do: "Audible"
end
