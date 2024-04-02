defmodule AmbryWeb.DownloadController do
  use AmbryWeb, :controller

  alias Ambry.Hashids
  alias Ambry.Media
  alias Ambry.SupplementalFile

  def download_media(conn, params) do
    with {:ok, [media_id]} <- Hashids.decode(params["media_id"]),
         {:ok, media} <- Media.fetch_media(media_id),
         %SupplementalFile{} = file <-
           Enum.find(media.supplemental_files, &(&1.id == params["file_id"])) do
      path = file.path |> Path.basename() |> Ambry.Paths.supplemental_files_disk_path()

      send_download(conn, {:file, path},
        filename: file.filename,
        content_type: file.mime,
        disposition: :inline
      )
    else
      _else ->
        conn
        |> put_status(:not_found)
        |> put_layout(false)
        |> put_view(AmbryWeb.ErrorHTML)
        |> render(:"404")
    end
  end
end
