defmodule AmbryWeb.Admin.UploadLive.New do
  @moduledoc false

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.UploadHelpers

  alias Ambry.{Paths, Uploads}
  alias Ambry.Metadata.FFProbe
  alias Ambry.Uploads.Upload

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> allow_audio_upload(:audio_files)
      |> assign(header_title: "Upload")
      |> assign_form(Uploads.change_upload(%Upload{}))

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.simple_form for={@form} phx-change="validate" phx-submit="save">
      <div class="space-y-2">
        <.label>Book title</.label>
        <.note>
          This will help during the import process to correctly identify the book you're uploading
          file(s) for. Use the book title only here, don't include the authors, narrators, or
          series name. Leave this blank and we'll try and determine the title from the file(s).
        </.note>
        <.input field={@form[:title]} placeholder="The Hobbit" />
      </div>

      <div class="space-y-2">
        <.label>Upload audio file(s)</.label>

        <.note>
          <:label>Supported formats</:label>
          mp3, mp4, m4a, m4b
        </.note>

        <section
          class="mt-2 w-full space-y-4 rounded-lg border-2 border-dashed border-lime-400 p-4"
          phx-drop-target={@uploads.audio_files.ref}
        >
          <.live_file_input upload={@uploads.audio_files} />
          <article :for={entry <- @uploads.audio_files.entries} class="upload-entry">
            <figure>
              <figcaption><%= entry.client_name %></figcaption>
            </figure>

            <progress value={entry.progress} max="100"><%= entry.progress %>%</progress>

            <span
              class="cursor-pointer text-2xl transition-colors hover:text-red-600"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
            >
              &times;
            </span>

            <p :for={err <- upload_errors(@uploads.audio_files, entry)} class="text-red-600">
              <%= error_to_string(err) %>
            </p>
          </article>
        </section>
      </div>

      <:actions>
        <.button>Save</.button>
      </:actions>
    </.simple_form>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"upload" => upload_params}, socket) do
    changeset =
      %Upload{}
      |> Uploads.change_upload(upload_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"upload" => upload_params}, socket) do
    folder_id = Ecto.UUID.generate()
    source_folder = Paths.source_media_disk_path(folder_id)

    files_params =
      consume_uploaded_entries(socket, :audio_files, fn %{path: path}, entry ->
        File.mkdir_p!(source_folder)

        dest = Path.join([source_folder, entry.client_name])
        File.cp!(path, dest)

        {:ok,
         %{
           path: Paths.disk_to_web(dest),
           filename: entry.client_name,
           size: entry.client_size,
           mime: entry.client_type
         }}
      end)

    {:ok, upload} = Uploads.create_upload(Map.merge(upload_params, %{"files" => files_params}))
    {:ok, upload} = Uploads.add_metadata(upload, FFProbe)
    # TODO: infer title here if none was given and update the upload with it

    {:noreply, push_navigate(socket, to: ~p"/admin/upload/#{upload.id}")}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio_files, ref)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
