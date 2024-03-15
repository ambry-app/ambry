defmodule AmbryWeb.Admin.MediaLive.Form do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  import Ambry.Paths
  import AmbryWeb.Admin.ParamHelpers
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Media
  alias Ambry.Media.Processor
  alias Ambry.Media.ProcessorJob
  alias AmbryWeb.Admin.MediaLive.Form.AudibleImportForm
  alias AmbryWeb.Admin.MediaLive.Form.GoodreadsImportForm
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> allow_audio_upload(:audio)
     |> allow_supplemental_file_upload(:supplemental)
     |> assign(
       import: nil,
       scraping_available: AmbryScraping.web_scraping_available?(),
       source_files_expanded: false,
       narrators: Ambry.Narrators.for_select(),
       books: Ambry.Books.for_select()
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    media = Media.get_media!(id)
    changeset = Media.change_media(media, %{}, for: :update)

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
    changeset = Media.change_media(media, %{}, for: :create)

    socket
    |> assign_form(changeset)
    |> assign(
      page_title: "New Media",
      media: media,
      file_stats: nil
    )
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"media" => media_params}, socket) do
    changeset =
      socket.assigns.media
      |> Media.change_media(media_params, for: changeset_action(socket.assigns.live_action))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"media" => media_params}, socket) do
    with :ok <- changeset_valid?(socket, media_params),
         {:ok, media_params} <-
           handle_supplemental_files_upload(socket, media_params, :supplemental),
         {:ok, media_params} <- handle_audio_files_upload(socket, media_params, :audio) do
      save_media(socket, socket.assigns.live_action, media_params)
    else
      {:error, %Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("open-import-form", %{"type" => type}, socket) do
    query =
      case Map.fetch(socket.assigns.form.params, "book_id") do
        {:ok, book_id} ->
          book = Ambry.Books.get_book!(book_id)
          book.title

        :error ->
          ""
      end

    import_type = String.to_existing_atom(type)
    socket = assign(socket, import: %{type: import_type, query: query})
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  def handle_event("cancel-import", _params, socket) do
    {:noreply, assign(socket, import: nil)}
  end

  @impl Phoenix.LiveView
  def handle_info({:import, %{"media" => media_params}}, socket) do
    # narrators could have been created, reload the data-lists
    socket =
      assign(socket,
        narrators: Ambry.Narrators.for_select()
      )

    new_params = Map.merge(socket.assigns.form.params, media_params)

    changeset =
      Media.change_media(socket.assigns.media, new_params,
        for: changeset_action(socket.assigns.live_action)
      )

    {:noreply, socket |> assign_form(changeset) |> assign(import: nil)}
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

  defp handle_audio_files_upload(socket, media_params, name) do
    folder_id = Media.Media.source_id(socket.assigns.media)
    source_folder = source_media_disk_path(folder_id)

    audio_files =
      consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
        File.mkdir_p!(source_folder)

        dest = Path.join([source_folder, entry.client_name])
        File.cp!(path, dest)

        {:ok, dest}
      end)

    media_params =
      if audio_files != [] do
        Map.put(media_params, "source_path", source_folder)
      else
        media_params
      end

    {:ok, media_params}
  end

  defp changeset_valid?(socket, media_params) do
    case Media.change_media(socket.assigns.media, media_params,
           for: changeset_action(socket.assigns.live_action)
         ) do
      %{valid?: true} -> :ok
      # if the _only_ error is the missing source-path, then we let it pass (at first)
      %{errors: [source_path: {"can't be blank", [validation: :required]}]} -> :ok
      changeset -> {:error, Map.put(changeset, :action, :validate)}
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

  defp open_import_form(type), do: JS.push("open-import-form", value: %{"type" => type})
end
