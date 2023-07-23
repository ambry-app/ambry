defmodule AmbryWeb.Admin.BookLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Books
  alias Ambry.Books.Book
  alias AmbryWeb.Admin.BookLive.Form.AudibleImportForm
  alias AmbryWeb.Admin.BookLive.Form.GoodreadsImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> allow_image_upload(:image)
     |> assign(
       import: nil,
       authors: Ambry.Authors.for_select(),
       series: Ambry.Series.for_select()
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    book = Books.get_book!(id)
    init_params = if book.image_path, do: %{}, else: %{"image_type" => "upload"}
    changeset = Books.change_book(book, init_params)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: book.title,
      book: book
    )
  end

  defp apply_action(socket, :new, _params) do
    book = %Book{}
    changeset = Books.change_book(book, %{"image_type" => "upload"})

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Book",
      book: book
    )
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"book" => book_params}, socket) do
    socket =
      if book_params["image_type"] != "upload" do
        cancel_all_uploads(socket, :image)
      else
        socket
      end

    changeset =
      socket.assigns.book
      |> Books.change_book(book_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"import" => import_type, "book" => book_params}, socket) do
    changeset =
      socket.assigns.book
      |> Books.change_book(book_params)
      |> Map.put(:action, :validate)

    if Keyword.has_key?(changeset.errors, :title) do
      {:noreply, assign_form(socket, changeset)}
    else
      socket = assign(socket, import: %{type: String.to_existing_atom(import_type), query: book_params["title"]})

      {:noreply, socket}
    end
  end

  def handle_event("submit", %{"book" => book_params}, socket) do
    with {:ok, _book} <-
           socket.assigns.book |> Books.change_book(book_params) |> Changeset.apply_action(:insert),
         {:ok, book_params} <- handle_image_upload(socket, book_params, :image),
         {:ok, book_params} <- handle_image_import(book_params["image_import_url"], book_params) do
      save_book(socket, socket.assigns.live_action, book_params)
    else
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, :failed_upload} -> {:noreply, put_flash(socket, :error, "Failed to upload image")}
      {:error, :failed_import} -> {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("cancel-import", _params, socket) do
    {:noreply, assign(socket, import: nil)}
  end

  @impl Phoenix.LiveView
  def handle_info({:import, %{"book" => book_params}}, socket) do
    new_params = Map.merge(socket.assigns.form.params, book_params)
    changeset = Books.change_book(socket.assigns.book, new_params)
    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
  end

  # Forwards `handle_info` messages from `Task`s to live component
  def handle_info({_task_ref, {{:for, component, id}, payload}}, socket) do
    send_update(component, id: id, info: payload)
    {:noreply, socket}
  end

  def handle_info({:DOWN, _task_ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  defp cancel_all_uploads(socket, upload) do
    Enum.reduce(socket.assigns.uploads[upload].entries, socket, fn entry, socket ->
      cancel_upload(socket, upload, entry.ref)
    end)
  end

  defp handle_image_upload(socket, book_params, name) do
    case consume_uploaded_image(socket, name) do
      {:ok, :no_file} -> {:ok, book_params}
      {:ok, path} -> {:ok, Map.put(book_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_upload}
    end
  end

  defp handle_image_import(url, book_params) do
    case handle_image_import(url) do
      {:ok, :no_image_url} -> {:ok, book_params}
      {:ok, path} -> {:ok, Map.put(book_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_import}
    end
  end

  defp save_book(socket, :edit, book_params) do
    case Books.update_book(socket.assigns.book, book_params) do
      {:ok, book} ->
        {:noreply,
         socket
         |> put_flash(:info, "Updated #{book.title}")
         |> push_navigate(to: ~p"/admin/books")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_book(socket, :new, book_params) do
    case Books.create_book(book_params) do
      {:ok, book} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created #{book.title}")
         |> push_navigate(to: ~p"/admin/books")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp import_form(:goodreads), do: GoodreadsImportForm
  defp import_form(:audible), do: AudibleImportForm

  # defp async_import_search(socket, :goodreads, query),
  #   do: do_async_import_search(socket, :goodreads, query, &GoodReads.search_books/1)

  # defp async_import_search(socket, :audible, query),
  #   do: do_async_import_search(socket, :audible, query, &Audible.search_books/1)

  # defp do_async_import_search(socket, import_type, query, query_fun) do
  #   Task.async(fn ->
  #     response = query_fun.(query |> String.trim() |> String.downcase())
  #     {import_type, :search, response}
  #   end)

  #   assign(socket,
  #     import: %{
  #       type: import_type,
  #       search_form: to_form(%{"query" => query}, as: :import_search),
  #       search_loading: true,
  #       results: nil,
  #       selected_book: nil
  #       # editions_loading: false,
  #       # editions: nil,
  #       # details_loading: false,
  #       # details: nil,
  #       # form: to_form(init_import_form_params(socket.assigns.book), as: :import)
  #     }
  #   )
  # end

  # defp async_import_editions(socket, :goodreads, book_id) do
  #   Task.async(fn ->
  #     response = GoodReads.editions(book_id)
  #     {:goodreads, :editions, response}
  #   end)

  #   update(socket, :import, fn import_assigns ->
  #     %{
  #       import_assigns
  #       | editions_loading: true,
  #         editions: nil
  #     }
  #   end)
  # end

  # defp async_import_details(socket, :goodreads, edition_id) do
  #   Task.async(fn ->
  #     response = GoodReads.edition_details(edition_id)
  #     {:goodreads, :details, response}
  #   end)

  #   update(socket, :import, fn import_assigns ->
  #     %{
  #       import_assigns
  #       | details_loading: true,
  #         details: nil
  #     }
  #   end)
  # end

  # # defp async_import_details(socket, :goodreads, author_id),
  # #   do: do_async_import_details(socket, :goodreads, author_id, &GoodReads.author/1)

  # # defp async_import_details(socket, :audible, author_id),
  # #   do: do_async_import_details(socket, :audible, author_id, &Audible.author/1)

  # # defp do_async_import_details(socket, import_type, author_id, details_fun) do
  # #   Task.async(fn ->
  # #     response = details_fun.(author_id)
  # #     {import_type, :details, response}
  # #   end)

  # #   update(socket, :import, fn import_assigns ->
  # #     %{
  # #       import_assigns
  # #       | details_form: to_form(%{"author_id" => author_id}, as: :import_details),
  # #         details_loading: true,
  # #         details: nil
  # #     }
  # #   end)
  # # end

  # defp init_import_form_params(book) do
  #   Map.new([:title, :description, :image], fn
  #     :title -> {"use_title", is_nil(book.title)}
  #     :description -> {"use_description", is_nil(book.description)}
  #     :image -> {"use_image", is_nil(book.image_path)}
  #   end)
  # end

  ## components

  # attr :book, :any, required: true
  # slot :actions

  # defp book_card(%{book: %AmbryScraping.GoodReads.Books.Search.Book{}} = assigns) do
  #   ~H"""
  #   <div class="flex gap-2 text-sm">
  #     <img src={@book.thumbnail.data_url} class="object-contain object-top" />
  #     <div>
  #       <p class="font-bold"><%= @book.title %></p>
  #       <p class="text-zinc-400">
  #         by
  #         <span :for={contributor <- @book.contributors} class="group">
  #           <span><%= contributor.name %></span>
  #           <span class="text-xs text-zinc-600">(<%= contributor.type %>)</span>
  #           <br class="group-last:hidden" />
  #         </span>
  #       </p>
  #       <div :for={action <- @actions}>
  #         <%= render_slot(action) %>
  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  # defp book_card(%{book: %AmbryScraping.GoodReads.Books.Editions.Edition{}} = assigns) do
  #   ~H"""
  #   <div class="flex gap-2 text-sm">
  #     <img src={@book.thumbnail.data_url} class="object-contain object-top" />
  #     <div>
  #       <p class="font-bold"><%= @book.title %></p>
  #       <p class="text-zinc-400">
  #         by
  #         <span :for={contributor <- @book.contributors} class="group">
  #           <span><%= contributor.name %></span>
  #           <span class="text-xs text-zinc-600">(<%= contributor.type %>)</span>
  #           <br class="group-last:hidden" />
  #         </span>
  #       </p>
  #       <p :if={@book.published && @book.publisher} class="text-xs text-zinc-400">
  #         Published <%= display_date(@book.published) %> by <%= @book.publisher %>
  #       </p>
  #       <p class="text-xs text-zinc-400"><%= @book.format %></p>
  #       <div :for={action <- @actions}>
  #         <%= render_slot(action) %>
  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  # defp book_card(%{book: %AmbryScraping.Audible.Products.Product{}} = assigns) do
  #   ~H"""
  #   <div class="flex gap-2 text-sm">
  #     <img src={@book.cover_image.src} class="h-24 w-24" />
  #     <div>
  #       <p class="font-bold"><%= @book.title %></p>
  #       <p :if={@book.authors != []} class="text-zinc-400">
  #         by
  #         <span :for={author <- @book.authors} class="group">
  #           <span><%= author.name %></span>
  #           <br class="group-last:hidden" />
  #         </span>
  #       </p>
  #       <p :if={@book.narrators != []} class="text-zinc-400">
  #         Narrated by
  #         <span :for={narrator <- @book.narrators} class="group">
  #           <span><%= narrator.name %></span>
  #           <br class="group-last:hidden" />
  #         </span>
  #       </p>
  #       <p :if={@book.published && @book.publisher} class="text-xs text-zinc-400">
  #         Published <%= display_date(@book.published) %> by <%= @book.publisher %>
  #       </p>
  #       <p class="text-xs text-zinc-400"><%= @book.format %></p>
  #       <div :for={action <- @actions}>
  #         <%= render_slot(action) %>
  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  # defp display_date(%Date{} = date), do: Calendar.strftime(date, "%B %-d, %Y")

  # defp display_date(%AmbryScraping.GoodReads.PublishedDate{display_format: :full, date: date}),
  #   do: Calendar.strftime(date, "%B %-d, %Y")

  # defp display_date(%AmbryScraping.GoodReads.PublishedDate{display_format: :year_month, date: date}),
  #   do: Calendar.strftime(date, "%B %Y")

  # defp display_date(%AmbryScraping.GoodReads.PublishedDate{display_format: :year, date: date}),
  #   do: Calendar.strftime(date, "%Y")
end
