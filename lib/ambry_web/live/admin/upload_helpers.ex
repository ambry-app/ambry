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
    allow_upload(socket, name, accept: @accepted_extensions, max_entries: 1)
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
        filename = save_image_to_disk!(entry.client_type, File.read!(path))

        {:ok, ~p"/uploads/images/#{filename}"}
      end)

    case uploaded_files do
      [path] -> {:ok, path}
      [] -> {:ok, :no_file}
      _else -> {:error, :too_many_files}
    end
  end

  defp save_image_to_disk!(mime, data) do
    hash = Base.encode16(:crypto.hash(:md5, data), case: :lower)
    [ext | _] = MIME.extensions(mime)
    filename = "#{hash}.#{ext}"
    dest = images_disk_path(filename)
    File.write!(dest, data)

    filename
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:too_many_files), do: "You have selected too many files"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

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
         [mime | _rest] <- Req.Response.get_header(response, "content-type") do
      filename = save_image_to_disk!(mime, response.body)

      {:ok, ~p"/uploads/images/#{filename}"}
    else
      _term -> {:error, :failed_to_download_image}
    end
  end

  def valid_image_url?(string) when is_binary(string) do
    case URI.new(string) do
      {:ok, %{scheme: scheme}} when is_binary(scheme) -> MIME.from_path(string) in @accepted_mime
      _term -> false
    end
  end

  def valid_image_url?(_term), do: false
end
