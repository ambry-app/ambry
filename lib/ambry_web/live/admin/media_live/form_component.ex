defmodule AmbryWeb.Admin.MediaLive.FormComponent do
  use AmbryWeb, :live_component

  import Ambry.Paths

  alias Ambry.{Books, Narrators, Media}
  alias Ambry.Media.Processor

  alias Surface.Components.{Form, LiveFileInput}

  alias Surface.Components.Form.{
    Checkbox,
    ErrorTag,
    Field,
    HiddenInputs,
    Inputs,
    Label,
    Select,
    Submit
  }

  prop title, :string, required: true
  prop media, :any, required: true
  prop action, :atom, required: true
  prop return_to, :string, required: true

  @impl true
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

  @impl true
  def update(%{media: media} = assigns, socket) do
    changeset = Media.change_media(media, init_media_param(media))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"media" => media_params}, socket) do
    media_params = clean_media_params(media_params)

    changeset =
      socket.assigns.media
      |> Media.change_media(media_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"media" => media_params}, socket) do
    folder_id = Ecto.UUID.generate()
    folder = Path.join([uploads_path(), "source_media"])

    consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
      File.mkdir_p!(Path.join([folder, folder_id]))

      dest = Path.join([folder, folder_id, entry.client_name])
      File.cp!(path, dest)
    end)

    media_params =
      Map.merge(media_params, %{
        "source_path" => Path.join([folder, folder_id]),
        "status" => :pending
      })

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
    case Media.update_media(socket.assigns.media, media_params) do
      {:ok, _media} ->
        {:noreply,
         socket
         |> put_flash(:info, "Media updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_media(socket, :new, media_params) do
    case Media.create_media(media_params) do
      {:ok, media} ->
        {:ok, _job} = %{media_id: media.id} |> Processor.new() |> Oban.insert()

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

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:too_many_files), do: "You have selected too many files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

  defp map_to_list(params, key) do
    if Map.has_key?(params, key) do
      Map.update!(params, key, fn
        params_map when is_map(params_map) ->
          params_map
          |> Enum.sort_by(fn {index, _params} -> String.to_integer(index) end)
          |> Enum.map(fn {_index, params} -> params end)

        params_list when is_list(params_list) ->
          params_list
      end)
    else
      Map.put(params, key, [])
    end
  end

  defp init_media_param(media) do
    %{
      "media_narrators" => Enum.map(media.media_narrators, &%{"id" => &1.id})
    }
  end
end
