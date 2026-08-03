defmodule AmbryWeb.Admin.UploadHelpers do
  @moduledoc """
  Helpers for handling file uploads.
  """

  use AmbryWeb, :verified_routes

  import Ambry.Paths
  import Phoenix.LiveView, only: [allow_upload: 3]
  import Phoenix.LiveView.Upload, only: [consume_uploaded_entries: 3]

  @accepted_extensions ~w(.jpg .jpeg .png .webp)

  def allow_image_upload(socket, name) do
    allow_upload(socket, name, accept: @accepted_extensions, max_entries: 1, auto_upload: true)
  end

  def allow_audio_upload(socket, name) do
    allow_upload(socket, name,
      accept: ~w(.mp3 .mp4 .m4a .m4b .opus),
      max_entries: 200,
      max_file_size: 1_500_000_000,
      auto_upload: true
    )
  end

  def allow_supplemental_file_upload(socket, name) do
    allow_upload(socket, name,
      accept: :any,
      max_entries: 10,
      max_file_size: 52_428_800,
      auto_upload: true
    )
  end

  @doc """
  Consumes zero or one uploaded images from a socket and puts it in the uploaded
  images folder.

  Returns either `{:ok, path | :no_file}` or `{:error, :too_many_files}`; raises
  on file operation errors.
  """
  def consume_uploaded_image(socket, name) do
    uploaded_files =
      consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
        filename = generate_filename(entry.client_type)
        File.cp!(path, images_disk_path(filename))

        {:ok, ~p"/uploads/images/#{filename}"}
      end)

    case uploaded_files do
      [path] -> {:ok, path}
      [] -> {:ok, :no_file}
      _else -> {:error, :too_many_files}
    end
  end

  @doc """
  Consumes zero or more uploaded files from a socket and puts them in the
  supplemental files folder.

  Returns `[%{filename: "foo.pdf", path: path}]`; raises on file operation
  errors.
  """
  def consume_uploaded_supplemental_files(socket, name) do
    consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
      filename = generate_filename(entry.client_type)
      File.cp!(path, supplemental_files_disk_path(filename))

      {:ok,
       %{
         filename: entry.client_name,
         mime: entry.client_type,
         path: ~p"/uploads/supplemental/#{filename}"
       }}
    end)
  end

  defp generate_filename(mime) do
    uuid = Ecto.UUID.generate()
    [ext | _] = MIME.extensions(mime)

    "#{uuid}.#{ext}"
  end

  # The import itself lives in `Ambry.Images` — the inbox needs it too, and
  # `Ambry.Inbox` can't reach into the web layer.
  defdelegate handle_image_import(url), to: Ambry.Images, as: :import_url
  defdelegate valid_image_url?(string), to: Ambry.Images, as: :valid_url?
  defdelegate valid_image?(uri), to: Ambry.Images, as: :head_says_image?
  defdelegate image?(mime), to: Ambry.Images, as: :image_mime?

  def upload_error_to_string(:too_large), do: "File is too large"
  def upload_error_to_string(:too_many_files), do: "Too many files"
  def upload_error_to_string(:not_accepted), do: "Unacceptable file type"
end
