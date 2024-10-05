defmodule AmbryWeb.Admin.MediaLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  import Ambry.Paths
  import AmbryWeb.Admin.ParamHelpers
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Media
  alias Ambry.Media.Processor
  alias Ambry.Media.ProcessorJob
  alias Ambry.People
  alias AmbryWeb.Admin.MediaLive.Form.AudibleImportForm
  alias AmbryWeb.Admin.MediaLive.Form.FileBrowser
  alias AmbryWeb.Admin.MediaLive.Form.GoodreadsImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> allow_image_upload(:image)
     |> allow_audio_upload(:audio)
     |> allow_supplemental_file_upload(:supplemental)
     |> assign(
       import: nil,
       select_files: false,
       selected_files: MapSet.new(),
       scraping_available: AmbryScraping.web_scraping_available?(),
       source_files_expanded: false,
       narrators: People.narrators_for_select(),
       books: Ambry.Books.books_for_select(),
       local_import_path: Ambry.Paths.local_import_path()
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    media = Media.get_media!(id)

    changeset =
      Media.change_media(
        media,
        %{"image_type" => "upload", "source_type" => default_source_type(socket)},
        for: :update
      )

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: media.book.title,
      media: media,
      file_stats: Media.get_media_file_details(media)
    )
  end

  defp apply_action(socket, :new, _params) do
    media = %Media.Media{media_narrators: []}

    changeset =
      Media.change_media(
        media,
        %{"image_type" => "upload", "source_type" => default_source_type(socket)},
        for: :create
      )

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Media",
      media: media,
      file_stats: nil
    )
  end

  defp default_source_type(socket) do
    if socket.assigns.local_import_path do
      "local_import"
    else
      "upload"
    end
  end

  @impl Phoenix.LiveView
  def handle_params(%{"import" => type}, _url, socket) do
    book_id = socket.assigns.form.params["book_id"] || socket.assigns.media.book_id

    query =
      if book_id do
        Ambry.Books.get_book!(book_id).title
      else
        ""
      end

    import_type = String.to_existing_atom(type)
    {:noreply, assign(socket, import: %{type: import_type, query: query})}
  end

  def handle_params(%{"browse" => _}, _url, socket) do
    {:noreply, assign(socket, select_files: true)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, import: nil, select_files: false)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"media" => media_params}, socket) do
    socket =
      if media_params["image_type"] == "upload" do
        socket
      else
        cancel_all_uploads(socket, :image)
      end

    changeset =
      socket.assigns.media
      |> Media.change_media(media_params, for: changeset_action(socket.assigns.live_action))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"media" => media_params}, socket) do
    with :ok <- changeset_valid?(socket, media_params),
         {:ok, media_params} <- handle_image_upload(socket, media_params, :image),
         {:ok, media_params} <-
           handle_image_import(media_params["image_import_url"], media_params),
         {:ok, media_params} <-
           handle_supplemental_files_upload(socket, media_params, :supplemental),
         {:ok, media_params} <- handle_audio_files_upload(socket, media_params, :audio),
         {:ok, media_params} <- handle_audio_files_import(socket, media_params) do
      save_media(socket, socket.assigns.live_action, media_params)
    else
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, :failed_upload} -> {:noreply, put_flash(socket, :error, "Failed to upload image")}
      {:error, :failed_import} -> {:noreply, put_flash(socket, :error, "Failed to import image")}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  def handle_event("cancel-supplemental-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :supplemental, ref)}
  end

  @impl Phoenix.LiveView
  def handle_info({:import, %{"media" => media_params}}, socket) do
    # narrators could have been created, reload the data-lists
    socket =
      assign(socket,
        narrators: People.narrators_for_select()
      )

    new_params = Map.merge(socket.assigns.form.params, media_params)

    changeset =
      Media.change_media(socket.assigns.media, new_params,
        for: changeset_action(socket.assigns.live_action)
      )

    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
  end

  def handle_info({:files_selected, files}, socket) do
    {:noreply,
     socket
     |> assign(selected_files: files)
     |> push_patch(to: media_path(socket.assigns.media), replace: true)}
  end

  defp cancel_all_uploads(socket, upload) do
    Enum.reduce(socket.assigns.uploads[upload].entries, socket, fn entry, socket ->
      cancel_upload(socket, upload, entry.ref)
    end)
  end

  defp handle_supplemental_files_upload(socket, media_params, name) do
    uploaded_supplemental_files_params = consume_uploaded_supplemental_files(socket, name)

    {:ok,
     media_params
     |> Map.put_new("supplemental_files", [])
     |> Map.update!("supplemental_files", fn files_params ->
       map_to_list(files_params) ++ uploaded_supplemental_files_params
     end)}
  end

  defp handle_audio_files_upload(socket, %{"source_type" => "upload"} = media_params, name) do
    folder_id = Media.Media.source_id(socket.assigns.media)
    source_folder = source_media_disk_path(folder_id)

    audio_files =
      consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
        File.mkdir_p!(source_folder)

        dest = Path.join([source_folder, entry.client_name])
        File.cp!(path, dest)

        {:ok, dest}
      end)

    existing_source_files = socket.assigns.media.source_files

    media_params =
      if audio_files == [] do
        media_params
      else
        Map.merge(media_params, %{
          "source_path" => source_folder,
          "source_files" => Enum.sort(existing_source_files ++ audio_files, NaturalOrder)
        })
      end

    {:ok, media_params}
  end

  defp handle_audio_files_upload(_socket, media_params, _name) do
    {:ok, media_params}
  end

  defp handle_audio_files_import(socket, %{"source_type" => "local_import"} = media_params) do
    folder_id = Media.Media.source_id(socket.assigns.media)
    source_folder = source_media_disk_path(folder_id)

    existing_source_files = socket.assigns.media.source_files
    selected_files = Enum.to_list(socket.assigns.selected_files)
    new_source_files = Enum.sort(existing_source_files ++ selected_files, NaturalOrder)

    {:ok,
     Map.merge(media_params, %{
       "source_path" => source_folder,
       "source_files" => new_source_files
     })}
  end

  defp handle_audio_files_import(_socket, media_params) do
    {:ok, media_params}
  end

  defp changeset_valid?(socket, media_params) do
    case Media.change_media(socket.assigns.media, media_params,
           for: changeset_action(socket.assigns.live_action)
         ) do
      %{valid?: true} -> :ok
      # if the _only_ error is the missing source-path, then we let it pass (at first)
      %{errors: [source_path: {"can't be blank", [validation: :required]}]} -> :ok
      %Changeset{} = changeset -> {:error, Map.put(changeset, :action, :validate)}
    end
  end

  defp handle_image_upload(socket, media_params, name) do
    case consume_uploaded_image(socket, name) do
      {:ok, :no_file} -> {:ok, media_params}
      {:ok, path} -> {:ok, Map.put(media_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_upload}
    end
  end

  defp handle_image_import(url, media_params) do
    case handle_image_import(url) do
      {:ok, :no_image_url} -> {:ok, media_params}
      {:ok, path} -> {:ok, Map.put(media_params, "image_path", path)}
      {:error, _reason} -> {:error, :failed_import}
    end
  end

  defp save_media(socket, :edit, media_params) do
    case Media.update_media(socket.assigns.media, media_params, for: :update) do
      {:ok, media} ->
        maybe_start_processor!(media, media_params, :edit)

        {:noreply,
         socket
         |> put_flash(:info, "Updated media for #{media.book.title}")
         |> push_navigate(to: ~p"/admin/media")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_media(socket, :new, media_params) do
    case Media.create_media(media_params) do
      {:ok, media} ->
        media = Media.get_media!(media.id)
        maybe_start_processor!(media, media_params, :new)

        {:noreply,
         socket
         |> put_flash(:info, "Created new media for #{media.book.title}")
         |> push_navigate(to: ~p"/admin/media")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp changeset_action(:new), do: :create
  defp changeset_action(:edit), do: :update

  defp maybe_start_processor!(media, media_params, :new) do
    processor =
      case parse_requested_processor(media_params["processor"]) do
        :none_specified -> :auto
        processor -> processor
      end

    %{media_id: media.id, processor: processor}
    |> ProcessorJob.new()
    |> Oban.insert!()
  end

  defp maybe_start_processor!(media, media_params, :edit) do
    case parse_requested_processor(media_params["processor"]) do
      :none_specified ->
        :noop

      processor ->
        %{media_id: media.id, processor: processor}
        |> ProcessorJob.new()
        |> Oban.insert!()
    end
  end

  defp processors(%Media.Media{source_path: path} = media, [_ | _] = uploads)
       when is_binary(path) do
    filenames = Enum.map(uploads, & &1.client_name)
    {media, filenames} |> Processor.matched_processors() |> Enum.map(&{&1.name(), &1})
  end

  defp processors(_media, [_ | _] = uploads) do
    filenames = Enum.map(uploads, & &1.client_name)
    filenames |> Processor.matched_processors() |> Enum.map(&{&1.name(), &1})
  end

  defp processors(%Media.Media{source_path: path} = media, _uploads) when is_binary(path) do
    media |> Processor.matched_processors() |> Enum.map(&{&1.name(), &1})
  end

  defp processors(_media, _uploads), do: []

  defp parse_requested_processor(""), do: :none_specified
  defp parse_requested_processor(string), do: String.to_existing_atom(string)

  defp import_form(:goodreads), do: GoodreadsImportForm
  defp import_form(:audible), do: AudibleImportForm

  # Components

  attr :file, :any, required: true
  attr :label, :string, required: true
  attr :error_type, :atom, default: :error
  attr :class, :string, default: nil

  defp file_stat_row(assigns) do
    ~H"""
    <div class={[@class]}>
      <div class="flex p-2">
        <div class="w-28 pr-2">
          <.badge color={:gray}><%= @label %></.badge>
        </div>
        <%= if @file do %>
          <div class="grow break-all pr-2">
            <%= @file.path %>
          </div>
          <div class="shrink">
            <%= case @file.stat do %>
              <% error when is_atom(error) -> %>
                <.badge color={color_for_error_type(@error_type)}><%= error %></.badge>
              <% stat when is_map(stat) -> %>
                <.badge color={:blue}><%= format_filesize(stat.size) %></.badge>
            <% end %>
          </div>
        <% else %>
          <div class="grow" />
          <div class="shrink">
            <.badge color={:red}>nil</.badge>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp color_for_error_type(:error), do: :red
  defp color_for_error_type(:warn), do: :yellow

  defp format_filesize(bytes) do
    bytes |> FileSize.from_bytes() |> FileSize.scale() |> FileSize.format()
  end

  defp preview_date_format(form) do
    format_published(%{
      published_format: Ecto.Changeset.get_field(form.source, :published_format),
      published: Ecto.Changeset.get_field(form.source, :published)
    })
  end

  defp media_path(media, params \\ %{})
  defp media_path(%Media.Media{id: nil}, params), do: ~p"/admin/media/new?#{params}"
  defp media_path(media, params), do: ~p"/admin/media/#{media}/edit?#{params}"

  defp open_import_form(media, type), do: JS.patch(media_path(media, %{import: type}))
  defp open_file_browser(media), do: JS.patch(media_path(media, %{browse: :files}))
  defp close_modal(media), do: JS.patch(media_path(media), replace: true)
end
