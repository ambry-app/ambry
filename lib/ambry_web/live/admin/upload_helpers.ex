defmodule AmbryWeb.Admin.UploadHelpers do
  @moduledoc """
  Helpers for handling file uploads.
  """

  import Ambry.Paths
  import Phoenix.LiveView, only: [allow_upload: 3]
  import Phoenix.LiveView.Upload, only: [consume_uploaded_entries: 3]

  alias AmbryWeb.Router.Helpers, as: Routes

  def allow_image_upload(socket) do
    allow_upload(socket, :image, accept: ~w(.jpg .jpeg .png .webp), max_entries: 1)
  end

  @doc """
  Consumes zero or one uploaded images from a socket and puts it in the uploaded
  images folder.

  Returns either `{:ok, path | :no_file}` or `{:error, :too_many_files}`; raises
  on file operation errors.
  """
  def consume_uploaded_image(socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        data = File.read!(path)
        hash = Base.encode16(:crypto.hash(:md5, data), case: :lower)
        [ext | _] = MIME.extensions(entry.client_type)
        filename = "#{hash}.#{ext}"
        dest = images_disk_path(filename)
        File.cp!(path, dest)
        Routes.static_path(socket, "/uploads/images/#{filename}")
      end)

    case uploaded_files do
      [path] -> {:ok, path}
      [] -> {:ok, :no_file}
      _else -> {:error, :too_many_files}
    end
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:too_many_files), do: "You have selected too many files"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
end
