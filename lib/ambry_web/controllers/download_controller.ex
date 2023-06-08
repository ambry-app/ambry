defmodule AmbryWeb.DownloadController do
  use AmbryWeb, :controller

  alias Ambry.{Media, SupplementalFile}

  alias AmbryWeb.Hashids

  def download_media(conn, params) do
    with {:ok, [media_id]} <- Hashids.decode(params["media_id"]),
         {:ok, media} <- Media.get_media(media_id),
         %SupplementalFile{} = file <-
           Enum.find(media.supplemental_files, &(&1.id == params["file_id"])) do
      path = file.path |> Path.basename() |> Ambry.Paths.supplemental_files_disk_path()

      send_download(conn, {:file, path},
        filename: file.filename,
        content_type: file.mime,
        disposition: :inline
      )
    else
      _else -> text(conn, "hi")
    end
  end
end
