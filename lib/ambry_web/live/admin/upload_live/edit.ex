defmodule AmbryWeb.Admin.UploadLive.Edit do
  @moduledoc false

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Books
  alias Ambry.Uploads

  @initial_params %{"book" => %{"image_type" => "upload"}}

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    upload = Uploads.get_upload!(id)
    socket = allow_image_upload(socket, :book_cover_image)

    initial_params =
      cond do
        !is_nil(upload.book_id) ->
          Map.merge(@initial_params, %{"book_id" => to_string(upload.book_id)})

        is_binary(upload.title) ->
          case Ambry.Search.search(upload.title) do
            [%Books.Book{} = book | _rest] ->
              Map.merge(@initial_params, %{"book_id" => to_string(book.id)})

            _else ->
              @initial_params
          end

        true ->
          @initial_params
      end

    existing_book? = Map.has_key?(initial_params, "book_id") || !is_nil(upload.book_id)

    socket =
      socket
      |> assign(
        upload: upload,
        header_title:
          if(upload.title,
            do: "Editing upload for #{upload.title}",
            else: "Editing untitled upload"
          ),
        books: Books.for_select(),
        existing_book: existing_book?,
        goodreads: %{
          search_form: to_form(%{"query" => upload.title}, as: :goodreads_search),
          search_loading: false,
          error: nil,
          search: nil,
          selected_book: nil,
          editions_loading: false,
          editions: nil,
          selected_edition: nil,
          edition_details_loading: false,
          edition_details: nil
        }
      )
      |> assign_form(Uploads.change_upload(upload, initial_params))

    socket =
      if connected?(socket) && !existing_book? && upload.title do
        goodreads_search_async(socket, upload.title)
      else
        socket
      end

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.simple_form
      id={@goodreads.search_form.id}
      for={@goodreads.search_form}
      phx-change="goodreads-search-change"
      phx-submit="goodreads-search-submit"
    >
    </.simple_form>

    <.modal id="goodreads-selector-modal">
      <div class="grid grid-cols-2 gap-4">
        <div>
          <div :if={@goodreads.search} class="space-y-2">
            <.label>Results for "<%= @goodreads.search.query %>"</.label>
            <div
              :for={book <- @goodreads.search.results}
              class={[
                "cursor-pointer rounded-md p-2 hover:bg-zinc-900",
                if(@goodreads.selected_book.id == book.id, do: "bg-zinc-900")
              ]}
              phx-click={JS.push("goodreads-select-book", value: %{"book-id" => book.id})}
            >
              <.book_card book={book} />
            </div>
          </div>
        </div>
        <div>
          <.loading :if={@goodreads.editions_loading}>
            Fetching editions from GoodReads...
          </.loading>
          <div :if={@goodreads.editions} class="space-y-2">
            <.label>Editions for "<%= @goodreads.editions.title %>"</.label>
            <div
              :for={edition <- @goodreads.editions.editions}
              class={[
                "cursor-pointer rounded-md p-2 hover:bg-zinc-900",
                if(@goodreads.selected_edition.id == edition.id, do: "bg-zinc-900")
              ]}
              phx-click={
                hide_modal("goodreads-selector-modal")
                |> JS.push("goodreads-select-edition", value: %{"edition-id" => edition.id})
              }
            >
              <.book_card book={edition} />
            </div>
          </div>
        </div>
      </div>
    </.modal>

    <.simple_form for={@form} phx-change="validate" phx-submit="save">
      <.datalist id="books" options={@books} />

      <div class="space-y-6">
        <.input field={@form[:title]} label="Book title" />

        <div>
          <.label>Files</.label>
          <ul class="flex flex-wrap gap-2 text-zinc-500">
            <li :for={file <- Enum.sort_by(@upload.files, & &1.filename, NaturalOrder)}><%= file.filename %></li>
          </ul>
        </div>

        <fieldset class="space-y-2 rounded-md border-2 border-zinc-800 px-4 pb-4">
          <legend class="px-2 text-sm">
            <span class="flex flex-row">
              <span
                phx-click={if !@existing_book, do: "toggle-existing-book"}
                class={[
                  "pr-2 pl-1 border-r-2 border-zinc-800",
                  if(!@existing_book, do: "cursor-pointer text-zinc-400", else: "font-bold")
                ]}
              >
                Existing book
              </span>
              <span
                phx-click={if @existing_book, do: "toggle-existing-book"}
                class={["pl-2", if(@existing_book, do: "cursor-pointer text-zinc-400", else: "font-bold")]}
              >
                New book
              </span>
            </span>
          </legend>

          <div :if={@existing_book}>
            <.input field={@form[:book_id]} type="autocomplete" label="Book" options={@books} list="books" />
          </div>

          <div :if={!@existing_book}>
            <.inputs_for :let={book_form} field={@form[:book]}>
              <div class="grid grid-cols-3 gap-6">
                <%!-- Book Header --%>
                <div />

                <%!-- GoodReads Header --%>
                <div class="space-y-6">
                  <div class="space-y-2">
                    <.label for={@goodreads.search_form[:query].id}>
                      Import from GoodReads
                    </.label>
                    <div class="flex w-full gap-2">
                      <.input
                        form={@goodreads.search_form.id}
                        field={@goodreads.search_form[:query]}
                        disabled={
                          @goodreads.search_loading || @goodreads.editions_loading || @goodreads.edition_details_loading
                        }
                        container_class="grow"
                      />
                      <.button
                        form={@goodreads.search_form.id}
                        disabled={
                          @goodreads.search_loading || @goodreads.editions_loading || @goodreads.edition_details_loading
                        }
                      >
                        Search
                      </.button>
                    </div>
                    <.brand_link
                      :if={
                        @goodreads.search && !@goodreads.search_loading && !@goodreads.editions_loading &&
                          !@goodreads.edition_details_loading
                      }
                      phx-click={show_modal("goodreads-selector-modal")}
                      class="!font-normal block text-sm"
                    >
                      Change book or edition
                    </.brand_link>
                    <.error :if={@goodreads.error}>
                      <%= @goodreads.error %>
                    </.error>
                    <.loading :if={
                      @goodreads.search_loading || @goodreads.editions_loading || @goodreads.edition_details_loading
                    }>
                      Fetching data from GoodReads...
                    </.loading>
                  </div>
                </div>

                <%!-- Audible Header --%>
                <p>Audible Header</p>

                <%!-- Image --%>
                <div class="space-y-2">
                  <.label for={book_form[:image_type].id}>Image</.label>
                  <.note>For best results, use a square image.</.note>
                  <.input
                    type="select"
                    field={book_form[:image_type]}
                    options={[
                      {"Upload file", "upload"},
                      {"Import image from URL", "url_import"},
                      {"Import from API", "data_import"}
                    ]}
                  />
                  <div :if={book_form[:image_type].value == "upload"}>
                    <section
                      class="border-brand mt-2 w-full space-y-4 rounded-lg border-2 border-dashed p-4 dark:border-brand-dark"
                      phx-drop-target={@uploads.book_cover_image.ref}
                    >
                      <.live_file_input upload={@uploads.book_cover_image} />

                      <article :for={entry <- @uploads.book_cover_image.entries} class="upload-entry">
                        <figure>
                          <.live_img_preview
                            entry={entry}
                            class="h-48 rounded-lg border border-zinc-200 shadow-md dark:border-zinc-900"
                          />
                          <figcaption><%= entry.client_name %></figcaption>
                        </figure>

                        <progress value={entry.progress} max="100"><%= entry.progress %>%</progress>

                        <span
                          class="cursor-pointer text-2xl transition-colors hover:text-red-600 dark:hover:text-red-500"
                          phx-click="cancel-book-cover-image-upload"
                          phx-value-ref={entry.ref}
                        >
                          &times;
                        </span>

                        <p
                          :for={err <- upload_errors(@uploads.book_cover_image, entry)}
                          class="text-red-600 dark:text-red-500"
                        >
                          <%= error_to_string(err) %>
                        </p>
                      </article>
                    </section>
                  </div>
                  <div :if={book_form[:image_type].value == "url_import"} class="space-y-2">
                    <.input field={book_form[:image_import_url]} placeholder="https://some-image.com/url" />

                    <div :if={valid_image_url?(book_form[:image_import_url].value)}>
                      <img
                        src={book_form[:image_import_url].value}
                        class="mt-2 h-48 rounded-lg border border-zinc-200 shadow-md dark:border-zinc-900"
                      />
                    </div>
                  </div>
                  <div :if={book_form[:image_type].value == "data_import"} class="space-y-2">
                    <.input type="hidden" field={book_form[:image_import_data]} />

                    <img
                      :if={book_form[:image_import_data].value}
                      src={book_form[:image_import_data].value}
                      class="mt-2 h-48 rounded-lg border border-zinc-200 shadow-md dark:border-zinc-900"
                    />
                    <.note :if={!book_form[:image_import_data].value}>
                      Click "Use this image" from either the GoodReads or Audible search results
                      on the right to import the cover image from there.
                    </.note>
                  </div>
                </div>

                <%!-- GR Image --%>
                <div>
                  <div :if={@goodreads.edition_details} class="space-y-2">
                    <.label>Image</.label>
                    <img
                      src={@goodreads.edition_details.cover_image.data_url}
                      class="h-48 rounded-lg border border-zinc-200 shadow-md dark:border-zinc-900"
                    />
                    <.brand_link
                      phx-click={
                        JS.push("set-book-field",
                          value: %{"field" => "image_type", "value" => "data_import"}
                        )
                        |> JS.push("set-book-field",
                          value: %{
                            "field" => "image_import_data",
                            "value" => @goodreads.edition_details.cover_image.data_url
                          }
                        )
                      }
                      class="!font-normal block text-sm"
                    >
                      Use this image
                    </.brand_link>
                  </div>
                </div>

                <%!-- Audible Image --%>
                <p>Audible Image</p>

                <%!-- Title --%>
                <div class="space-y-2">
                  <.input field={book_form[:title]} label="Title" />
                </div>

                <%!-- GR Title --%>
                <div>
                  <div :if={@goodreads.edition_details} class="space-y-2">
                    <.label>Title</.label>
                    <div class="text-lg font-bold">
                      <%= @goodreads.edition_details.title %>
                    </div>
                    <.brand_link
                      phx-click={
                        JS.push("set-book-field", value: %{"field" => "title", "value" => @goodreads.edition_details.title})
                      }
                      class="!font-normal block text-sm"
                    >
                      Use this title
                    </.brand_link>
                  </div>
                </div>

                <%!-- Audible Title --%>
                <p>Audible Title</p>

                <%!-- Published --%>
                <div class="space-y-2">
                  <.label for={book_form[:published].id}>Published</.label>

                  <.note>
                    This is meant to be print publication date, not audiobook recording date.
                  </.note>

                  <div class="flex flex-row items-center gap-2">
                    <.input field={book_form[:published]} type="date" container_class="flex-grow" />
                    <.label for={book_form[:published_format].id}>Display format</.label>
                    <.input
                      field={book_form[:published_format]}
                      type="select"
                      container_class="flex-grow"
                      options={[{"Full Date", "full"}, {"Year & Month", "year_month"}, {"Year Only", "year"}]}
                    />
                  </div>
                </div>

                <%!-- GR Published --%>
                <div>
                  <div :if={@goodreads.editions} class="space-y-2">
                    <.label>Published</.label>
                    <div class="text-lg">
                      <%= display_date(@goodreads.editions.first_published) %>
                    </div>
                    <.brand_link
                      phx-click={
                        JS.push("set-book-field",
                          value: %{"field" => "published", "value" => @goodreads.editions.first_published.date}
                        )
                        |> JS.push("set-book-field",
                          value: %{
                            "field" => "published_format",
                            "value" => @goodreads.editions.first_published.display_format
                          }
                        )
                      }
                      class="!font-normal block text-sm"
                    >
                      Use this date
                    </.brand_link>
                  </div>
                </div>

                <%!-- Audible Published --%>
                <p>Audible Published</p>

                <%!-- Description --%>
                <div class="space-y-2">
                  <.input
                    type="textarea"
                    field={book_form[:description]}
                    label="Description"
                    phx-hook="maintain-attrs"
                    data-attrs="style"
                    class="h-64"
                  />
                </div>

                <%!-- GR Description --%>
                <div>
                  <div :if={@goodreads.edition_details} class="space-y-2">
                    <.label>Description</.label>
                    <.markdown
                      content={@goodreads.edition_details.description}
                      class="max-h-64 overflow-y-auto rounded-lg border border-zinc-800 p-2"
                    />
                    <.brand_link
                      phx-click={
                        JS.push("set-book-field",
                          value: %{"field" => "description", "value" => @goodreads.edition_details.description}
                        )
                      }
                      class="!font-normal block text-sm"
                    >
                      Use this description
                    </.brand_link>
                  </div>
                </div>

                <%!-- Audible Description --%>
                <p>Audible Description</p>
              </div>
            </.inputs_for>
          </div>
        </fieldset>
      </div>

      <:actions>
        <.button>Save</.button>
      </:actions>
    </.simple_form>
    """
  end

  attr :book, :any, required: true
  slot :actions

  defp book_card(%{book: %GoodReads.Books.Search.Book{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.thumbnail.data_url} class="object-contain object-top" />
      <div>
        <p class="font-bold"><%= @book.title %></p>
        <p class="text-zinc-400">
          by
          <span :for={contributor <- @book.contributors} class="group">
            <span><%= contributor.name %></span>
            <span class="text-xs text-zinc-600">(<%= contributor.type %>)</span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <div :for={action <- @actions}>
          <%= render_slot(action) %>
        </div>
      </div>
    </div>
    """
  end

  defp book_card(%{book: %GoodReads.Books.Editions.Edition{}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-sm">
      <img src={@book.thumbnail.data_url} class="object-contain object-top" />
      <div>
        <p class="font-bold"><%= @book.title %></p>
        <p class="text-zinc-400">
          by
          <span :for={contributor <- @book.contributors} class="group">
            <span><%= contributor.name %></span>
            <span class="text-xs text-zinc-600">(<%= contributor.type %>)</span>
            <br class="group-last:hidden" />
          </span>
        </p>
        <p :if={@book.published && @book.publisher} class="text-xs text-zinc-400">
          Published <%= display_date(@book.published) %> by <%= @book.publisher %>
        </p>
        <p class="text-xs text-zinc-400"><%= @book.format %></p>
        <div :for={action <- @actions}>
          <%= render_slot(action) %>
        </div>
      </div>
    </div>
    """
  end

  defp display_date(%GoodReads.PublishedDate{display_format: :full, date: date}),
    do: Calendar.strftime(date, "%B %-d, %Y")

  defp display_date(%GoodReads.PublishedDate{display_format: :year_month, date: date}),
    do: Calendar.strftime(date, "%B %Y")

  defp display_date(%GoodReads.PublishedDate{display_format: :year, date: date}), do: Calendar.strftime(date, "%Y")

  slot :inner_block, required: true

  defp loading(assigns) do
    ~H"""
    <p class="flex items-center gap-3 text-sm font-semibold leading-6">
      <FA.icon name="rotate" class="h-4 w-4 flex-none animate-spin fill-zinc-800 dark:fill-zinc-200" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"upload" => upload_params}, socket) do
    changeset =
      socket.assigns.upload
      |> Uploads.change_upload(upload_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"upload" => upload_params}, socket) do
    {:ok, upload} = Uploads.update_upload(socket.assigns.upload, upload_params)

    socket =
      socket
      |> assign(upload: upload)
      |> assign_form(Uploads.change_upload(upload, %{}))

    {:noreply, socket}
  end

  def handle_event("set-book-field", %{"field" => field, "value" => value}, socket) do
    params =
      socket.assigns.form.params
      |> Map.put_new("book", %{})
      |> put_in(["book", field], value)

    socket = assign_form(socket, Uploads.change_upload(socket.assigns.upload, params))

    {:noreply, socket}
  end

  def handle_event("toggle-existing-book", _params, socket) do
    {:noreply, assign(socket, existing_book: !socket.assigns.existing_book)}
  end

  def handle_event("goodreads-search-change", %{"goodreads_search" => goodreads_search_params}, socket) do
    {:noreply,
     update(socket, :goodreads, fn goodreads_assigns ->
       %{goodreads_assigns | search_form: to_form(goodreads_search_params, as: :goodreads_search)}
     end)}
  end

  def handle_event("goodreads-search-submit", %{"goodreads_search" => goodreads_search_params}, socket) do
    {:noreply,
     socket
     |> update(:goodreads, fn goodreads_assigns ->
       %{goodreads_assigns | search_form: to_form(goodreads_search_params, as: :goodreads_search)}
     end)
     |> goodreads_search_async(goodreads_search_params["query"])}
  end

  def handle_event("goodreads-select-book", %{"book-id" => book_id}, socket) do
    book = Enum.find(socket.assigns.goodreads.search.results, &(&1.id == book_id))

    socket = goodreads_editions_async(socket, book.id)

    {:noreply,
     update(socket, :goodreads, fn goodreads_assigns ->
       %{goodreads_assigns | selected_book: book}
     end)}
  end

  def handle_event("goodreads-select-edition", %{"edition-id" => edition_id}, socket) do
    edition = Enum.find(socket.assigns.goodreads.editions.editions, &(&1.id == edition_id))

    socket = goodreads_edition_details_async(socket, edition.id)

    {:noreply,
     update(socket, :goodreads, fn goodreads_assigns ->
       %{goodreads_assigns | selected_edition: edition}
     end)}
  end

  def handle_event("cancel-book-cover-image-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :book_cover_image, ref)}
  end

  @impl Phoenix.LiveView
  def handle_info({_task_ref, {:goodreads_search, response}}, socket) do
    socket =
      case response do
        {:ok, search} ->
          selected_book = List.first(search.results)

          socket = goodreads_editions_async(socket, selected_book.id)

          update(socket, :goodreads, fn goodreads_assigns ->
            %{
              goodreads_assigns
              | search_loading: false,
                search: search,
                selected_book: selected_book
            }
          end)

        {:error, _reason} ->
          update(socket, :goodreads, fn goodreads_assigns ->
            %{
              goodreads_assigns
              | search_loading: false,
                error: "Search failed"
            }
          end)
      end

    {:noreply, socket}
  end

  def handle_info({_task_ref, {:goodreads_editions, response}}, socket) do
    socket =
      case response do
        {:ok, editions} ->
          selected_edition =
            Enum.find(editions.editions, List.first(editions.editions), fn edition ->
              edition.format |> String.downcase() |> String.contains?("audio")
            end)

          socket = goodreads_edition_details_async(socket, selected_edition.id)

          update(socket, :goodreads, fn goodreads_assigns ->
            %{
              goodreads_assigns
              | editions_loading: false,
                editions: editions,
                selected_edition: selected_edition
            }
          end)

        {:error, _reason} ->
          update(socket, :goodreads, fn goodreads_assigns ->
            %{
              goodreads_assigns
              | editions_loading: false,
                error: "Listing editions failed"
            }
          end)
      end

    {:noreply, socket}
  end

  def handle_info({_task_ref, {:goodreads_edition_details, response}}, socket) do
    socket =
      case response do
        {:ok, edition_details} ->
          update(socket, :goodreads, fn goodreads_assigns ->
            %{
              goodreads_assigns
              | edition_details_loading: false,
                edition_details: edition_details
            }
          end)

        {:error, _reason} ->
          update(socket, :goodreads, fn goodreads_assigns ->
            %{
              goodreads_assigns
              | edition_details_loading: false,
                error: "Edition details failed to load"
            }
          end)
      end

    {:noreply, socket}
  end

  def handle_info({:DOWN, _task_ref, _, _, _}, socket) do
    {:noreply, socket}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp goodreads_search_async(socket, query) do
    query =
      query
      |> to_string()
      |> String.trim()
      |> String.downcase()

    if query != "" do
      Task.async(fn ->
        response = Ambry.Metadata.GoodReads.search(query)
        {:goodreads_search, response}
      end)

      update(socket, :goodreads, fn goodreads_assigns ->
        %{
          goodreads_assigns
          | search_loading: true,
            error: nil,
            search: nil,
            selected_book: nil,
            editions: nil,
            selected_edition: nil,
            edition_details: nil
        }
      end)
    else
      socket
    end
  end

  defp goodreads_editions_async(socket, book_id) do
    Task.async(fn ->
      response = Ambry.Metadata.GoodReads.editions(book_id)
      {:goodreads_editions, response}
    end)

    update(socket, :goodreads, fn goodreads_assigns ->
      %{
        goodreads_assigns
        | editions_loading: true,
          error: nil,
          editions: nil,
          selected_edition: nil,
          edition_details: nil
      }
    end)
  end

  defp goodreads_edition_details_async(socket, edition_id) do
    Task.async(fn ->
      response = Ambry.Metadata.GoodReads.edition_details(edition_id)
      {:goodreads_edition_details, response}
    end)

    update(socket, :goodreads, fn goodreads_assigns ->
      %{
        goodreads_assigns
        | edition_details_loading: true,
          error: nil,
          edition_details: nil
      }
    end)
  end
end
