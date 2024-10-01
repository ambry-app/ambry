defmodule AmbryWeb.Admin.UploadHelpers do
  @moduledoc """
  Helpers for handling file uploads.
  """

  use AmbryWeb, :verified_routes

  import Ambry.Paths
  import Phoenix.LiveView, only: [allow_upload: 3]
  import Phoenix.LiveView.Upload, only: [consume_uploaded_entries: 3]

  @accepted_extensions ~w(.jpg .jpeg .png .webp)
  @accepted_mime ~w(image/jpeg image/png image/webp)

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
        filename = save_file_to_disk!(entry.client_type, File.read!(path), &images_disk_path/1)

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
      filename =
        save_file_to_disk!(entry.client_type, File.read!(path), &supplemental_files_disk_path/1)

      {:ok,
       %{
         filename: entry.client_name,
         mime: entry.client_type,
         path: ~p"/uploads/supplemental/#{filename}"
       }}
    end)
  end

  defp save_file_to_disk!(mime, data, path_fun) do
    uuid = Ecto.UUID.generate()
    [ext | _] = MIME.extensions(mime)
    filename = "#{uuid}.#{ext}"
    dest = path_fun.(filename)
    File.write!(dest, data)

    filename
  end

  def handle_image_import(nil), do: {:ok, :no_image_url}
  def handle_image_import(""), do: {:ok, :no_image_url}

  def handle_image_import(url) do
    if valid_image_url?(url) do
      do_image_import(url)
    else
      {:error, :invalid_image_url}
    end
  end

  defp do_image_import(url) do
    with {:ok, response} <- Req.get(url),
         [mime | _rest] when mime in @accepted_mime <-
           Req.Response.get_header(response, "content-type") do
      filename = save_file_to_disk!(mime, response.body, &images_disk_path/1)

      {:ok, ~p"/uploads/images/#{filename}"}
    else
      _term -> {:error, :failed_to_download_image}
    end
  end

  def valid_image_url?(string) when is_binary(string) do
    case URI.new(string) do
      {:ok, %{scheme: scheme} = uri} when is_binary(scheme) ->
        image?(MIME.from_path(string)) or valid_image?(uri)

      _term ->
        false
    end
  end

  def valid_image_url?(_term), do: false

  def valid_image?(uri) do
    case Req.head(uri) do
      {:ok, response} ->
        [mime | _rest] = Req.Response.get_header(response, "content-type")
        image?(mime)

      _else ->
        false
    end
  end

  def image?("image/" <> _rest), do: true
  def image?(_mime), do: false

  def upload_error_to_string(:too_large), do: "File is too large"
  def upload_error_to_string(:too_many_files), do: "Too many files"
  def upload_error_to_string(:not_accepted), do: "Unacceptable file type"
end
