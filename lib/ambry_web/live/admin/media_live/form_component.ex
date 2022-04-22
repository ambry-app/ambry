defmodule AmbryWeb.Admin.MediaLive.FormComponent do
  @moduledoc false

  use AmbryWeb, :live_component

  import Ambry.Paths
  import AmbryWeb.Admin.ParamHelpers, only: [map_to_list: 2]
  import AmbryWeb.Admin.UploadHelpers, only: [error_to_string: 1]

  alias Ambry.{Books, Media, Narrators}
  alias Ambry.Media.{Processor, ProcessorJob}
  alias AmbryWeb.Admin.MediaLive.FileStatRow

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket =
      allow_upload(socket, :audio,
        accept: ~w(.mp3 .mp4 .m4a .m4b),
        max_entries: 200,
        max_file_size: 1_500_000_000
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
     |> assign(:changeset, changeset)
     |> assign(:source_files_expanded, false)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"media" => media_params}, socket) do
    media_params = clean_media_params(media_params)

    changeset =
      socket.assigns.media
      |> Media.change_media(media_params, for: changeset_action(socket.assigns.action))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"media" => media_params}, socket) do
    folder_id = Ecto.UUID.generate()
    folder = Path.join([uploads_folder_disk_path(), "source_media"])

    files =
      consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
        File.mkdir_p!(Path.join([folder, folder_id]))

        dest = Path.join([folder, folder_id, entry.client_name])
        File.cp!(path, dest)
      end)

    media_params =
      if files != [] do
        # only add source path if files were uploaded
        Map.merge(media_params, %{
          "source_path" => Path.join([folder, folder_id])
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
      socket.assigns.changeset.params
      |> map_to_list("media_narrators")
      |> Map.update!("media_narrators", fn media_narrators_params ->
        media_narrators_params ++ [%{}]
      end)

    changeset = Media.change_media(socket.assigns.media, params)

    {:noreply, assign(socket, :changeset, changeset)}
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
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
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
        # schedule processor job only on newly created media
        {:ok, _job} =
          %{media_id: media.id, processor: processor}
          |> ProcessorJob.new()
          |> Oban.insert()

        {:noreply,
         socket
         |> put_flash(:info, "Media created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
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

  defp processors(media, uploads) do
    case {media, uploads} do
      {_media, [_ | _] = uploads} ->
        filenames = Enum.map(uploads, & &1.client_name)
        filenames |> Processor.matched_processors() |> Enum.map(&{&1.name(), &1})

      {%Media.Media{source_path: path}, _uploads} when is_binary(path) ->
        media |> Processor.matched_processors() |> Enum.map(&{&1.name(), &1})

      _else ->
        []
    end
  end

  defp parse_requested_processor(""), do: :none_specified
  defp parse_requested_processor(string), do: String.to_existing_atom(string)
end
