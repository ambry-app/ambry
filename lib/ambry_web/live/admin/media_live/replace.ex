defmodule AmbryWeb.Admin.MediaLive.Replace do
  @moduledoc false
  use AmbryWeb, :admin_live_view

  import Ambry.Paths
  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.Media
  alias AmbryWeb.Admin.MediaLive.Form.FileBrowser
  alias Ecto.Changeset

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    media = Media.get_media!(id)
    local_import_path = Ambry.Paths.local_import_path()

    changeset =
      Media.change_media(media, %{"source_type" => default_source_type(local_import_path)})

    {:ok,
     socket
     |> allow_audio_upload(:audio)
     |> assign_form(changeset)
     |> assign(
       page_title: "Replace audio for #{Ambry.Media.Media.display_title(media)}",
       media: media,
       local_import_path: local_import_path,
       select_files: false,
       selected_files: MapSet.new()
     )}
  end

  defp default_source_type(nil), do: "upload"
  defp default_source_type(_local_import_path), do: "local_import"

  @impl Phoenix.LiveView
  def handle_params(%{"browse" => _}, _url, socket) do
    {:noreply, assign(socket, select_files: true)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, select_files: false)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"media" => media_params}, socket) do
    changeset =
      socket.assigns.media
      |> Media.change_media(media_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  def handle_event("submit", %{"media" => media_params}, socket) do
    case consume_audio_files(socket, media_params) do
      {:ok, source_path, source_files} ->
        attrs = %{
          source_path: source_path,
          source_files: source_files,
          processor: requested_processor(media_params)
        }

        case Media.replace_media(socket.assigns.media, attrs) do
          {:ok, media} ->
            {:noreply,
             socket
             |> put_flash(:info, "Replacing audio for #{media.book.title}")
             |> push_navigate(to: ~p"/admin/audiobooks")}

          {:error, %Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, :no_files} ->
        {:noreply, put_flash(socket, :error, "You must provide at least one audio file")}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:files_selected, files}, socket) do
    {:noreply,
     socket
     |> assign(selected_files: files)
     |> push_patch(to: ~p"/admin/audiobooks/#{socket.assigns.media}/replace", replace: true)}
  end

  # Consumes browser uploads into a fresh source folder — or brings the
  # server-side files selected via the file browser into one, since the
  # database no longer stores absolute paths. Returns the new source_path
  # and sorted source files in `/uploads/...` form.
  defp consume_audio_files(socket, %{"source_type" => "local_import"}) do
    case Enum.to_list(socket.assigns.selected_files) do
      [] ->
        {:error, :no_files}

      selected_files ->
        source_path = source_media_disk_path(Ecto.UUID.generate())

        files =
          for file <- selected_files do
            File.mkdir_p!(source_path)
            dest = Path.join(source_path, Path.basename(file))

            case File.ln(file, dest) do
              :ok -> :ok
              {:error, :eexist} -> :ok
              {:error, _reason} -> File.cp!(file, dest)
            end

            Ambry.Paths.disk_to_web(dest)
          end

        {:ok, Ambry.Paths.disk_to_web(source_path), Enum.sort(files, NaturalOrder)}
    end
  end

  defp consume_audio_files(socket, _media_params) do
    source_path = source_media_disk_path(Ecto.UUID.generate())

    audio_files =
      consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
        File.mkdir_p!(source_path)
        dest = Path.join([source_path, entry.client_name])
        File.cp!(path, dest)

        {:ok, Ambry.Paths.disk_to_web(dest)}
      end)

    case audio_files do
      [] -> {:error, :no_files}
      files -> {:ok, Ambry.Paths.disk_to_web(source_path), Enum.sort(files, NaturalOrder)}
    end
  end

  defp requested_processor(media_params) do
    case media_params["processor"] do
      blank when blank in [nil, ""] -> :auto
      string -> String.to_existing_atom(string)
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp processor_options(uploads, selected_files) do
    cond do
      uploads != [] ->
        uploads |> Enum.map(& &1.client_name) |> to_processor_options()

      not Enum.empty?(selected_files) ->
        selected_files |> Enum.map(&Path.basename/1) |> to_processor_options()

      true ->
        []
    end
  end

  defp to_processor_options(filenames) do
    filenames
    |> Media.available_processors()
    |> Enum.map(&{&1.name(), &1})
  end

  defp open_file_browser(media), do: JS.patch(~p"/admin/audiobooks/#{media}/replace?browse=files")

  defp close_file_browser(media),
    do: JS.patch(~p"/admin/audiobooks/#{media}/replace", replace: true)
end
