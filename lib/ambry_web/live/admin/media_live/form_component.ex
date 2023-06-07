defmodule AmbryWeb.Admin.MediaLive.FormComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  import Ambry.Paths
  import AmbryWeb.Admin.Components
  import AmbryWeb.Admin.ParamHelpers, only: [map_to_list: 2]
  import AmbryWeb.Admin.UploadHelpers, only: [error_to_string: 1]

  alias Ambry.{Books, Media, Narrators}
  alias Ambry.Media.{Processor, ProcessorJob}

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket =
      socket
      |> allow_upload(:audio,
        accept: ~w(.mp3 .mp4 .m4a .m4b .opus),
        max_entries: 200,
        max_file_size: 1_500_000_000
      )
      |> allow_upload(:supplemental,
        accept: :any,
        max_entries: 10,
        max_file_size: 50
      )

    {:ok,
     socket
     |> assign(:books, books())
     |> assign(:narrators, narrators())}
  end

  @impl Phoenix.LiveComponent
  def update(%{media: media} = assigns, socket) do
    changeset =
      Media.change_media(media, init_media_param(media), for: changeset_action(assigns.action))

    socket =
      if assigns.action == :edit do
        assign(socket, :file_stats, Media.get_media_file_details(media))
      else
        assign(socket, :file_stats, nil)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:source_files_expanded, false)
     |> assign_form(changeset)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"media" => media_params}, socket) do
    media_params = clean_media_params(media_params)

    changeset =
      socket.assigns.media
      |> Media.change_media(media_params, for: changeset_action(socket.assigns.action))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"media" => media_params}, socket) do
    folder_id = Media.Media.source_id(socket.assigns.media)
    source_folder = source_media_disk_path(folder_id)
    supplemental_folder = supplemental_files_disk_path(folder_id)

    audio_files =
      consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
        File.mkdir_p!(source_folder)

        dest = Path.join([source_folder, entry.client_name])
        File.cp!(path, dest)

        {:ok, dest}
      end)

    media_params =
      if audio_files != [] do
        Map.merge(media_params, %{
          "source_path" => source_folder
        })
      else
        media_params
      end

    save_media(socket, socket.assigns.action, media_params)
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  def handle_event("add-narrator", _params, socket) do
    params =
      socket.assigns.form.source.params
      |> map_to_list("media_narrators")
      |> Map.update!("media_narrators", fn media_narrators_params ->
        media_narrators_params ++ [%{}]
      end)

    changeset = Media.change_media(socket.assigns.media, params)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("expand", _params, socket) do
    {:noreply, assign(socket, :source_files_expanded, true)}
  end

  def handle_event("collapse", _params, socket) do
    {:noreply, assign(socket, :source_files_expanded, false)}
  end

  defp clean_media_params(params) do
    params
    |> map_to_list("media_narrators")
    |> Map.update!("media_narrators", fn media_narrators ->
      Enum.reject(media_narrators, fn media_narrator_params ->
        is_nil(media_narrator_params["id"]) && media_narrator_params["delete"] == "true"
      end)
    end)
  end

  defp save_media(socket, :edit, media_params) do
    case Media.update_media(socket.assigns.media, media_params, for: :update) do
      {:ok, media} ->
        case parse_requested_processor(media_params["processor"]) do
          :none_specified ->
            :noop

          processor ->
            {:ok, _job} =
              %{media_id: media.id, processor: processor}
              |> ProcessorJob.new()
              |> Oban.insert()
        end

        {:noreply,
         socket
         |> put_flash(:info, "Media updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_media(socket, :new, media_params) do
    processor =
      case parse_requested_processor(media_params["processor"]) do
        :none_specified -> :auto
        processor -> processor
      end

    case Media.create_media(media_params) do
      {:ok, media} ->
        {:ok, _job} =
          %{media_id: media.id, processor: processor}
          |> ProcessorJob.new()
          |> Oban.insert()

        {:noreply,
         socket
         |> put_flash(:info, "Media created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp books do
    Books.for_select()
  end

  defp narrators do
    Narrators.for_select()
  end

  defp init_media_param(media) do
    %{
      "media_narrators" => Enum.map(media.media_narrators, &%{"id" => &1.id})
    }
  end

  defp changeset_action(:new), do: :create
  defp changeset_action(:edit), do: :update

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

  attr :file, :any, required: true
  attr :label, :string, required: true
  attr :error_type, :atom, default: :error

  defp file_stat_row(assigns) do
    ~H"""
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
    """
  end

  defp color_for_error_type(:error), do: :red
  defp color_for_error_type(:warn), do: :yellow

  defp format_filesize(bytes) do
    bytes |> FileSize.from_bytes() |> FileSize.scale() |> FileSize.format()
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
