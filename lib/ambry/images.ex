defmodule Ambry.Images do
  @moduledoc """
  Bringing images into the uploads tree, from a URL or from inside an audio
  file.

  This lives in the core rather than the web layer because the inbox needs it:
  approval lands a recording's cover, and `Ambry.Inbox` cannot call into
  `AmbryWeb`. `AmbryWeb.Admin.UploadHelpers` delegates here, so there is one
  implementation of "download this and give me a web path" rather than two
  that drift.

  Everything written here is Ambry's own, under the uploads path — never a
  file the library references in place. That distinction is what makes these
  safe to delete with a record regardless of its custody.
  """

  import Ambry.Paths

  require Logger

  @accepted_mime ~w(image/jpeg image/png image/webp)

  @doc """
  Downloads an image and returns its web path.
  """
  def import_url(nil), do: {:ok, :no_image_url}
  def import_url(""), do: {:ok, :no_image_url}

  def import_url(url) do
    if valid_url?(url), do: download(url), else: {:error, :invalid_image_url}
  end

  defp download(url) do
    with {:ok, response} <- Req.get(url: url, headers: [{"user-agent", user_agent()}]),
         [mime | _rest] when mime in @accepted_mime <-
           Req.Response.get_header(response, "content-type") do
      filename = generate_filename(mime)
      File.write!(images_disk_path(filename), response.body)

      {:ok, web_path(filename)}
    else
      _term -> {:error, :failed_to_download_image}
    end
  end

  @doc """
  Extracts an audio file's embedded cover art and returns its web path.

  Cover art rides along as an `attached_pic` video stream, so pulling it out
  is a stream copy rather than a re-encode — `-c:v copy` keeps the publisher's
  original bytes instead of generationally re-compressing them.
  """
  def extract_embedded(audio_path) do
    filename = generate_filename("image/jpeg")
    destination = images_disk_path(filename)

    case ffmpeg(audio_path, destination) do
      {_output, 0} ->
        if File.exists?(destination) and File.stat!(destination).size > 0 do
          {:ok, web_path(filename)}
        else
          {:error, :no_embedded_image}
        end

      {output, status} ->
        Logger.warning(fn ->
          "Couldn't extract cover art from #{audio_path} (#{status}): #{output}"
        end)

        File.rm(destination)
        {:error, :no_embedded_image}
    end
  end

  defp ffmpeg(source, destination) do
    System.cmd(
      "ffmpeg",
      ["-nostdin", "-y", "-i", source, "-an", "-c:v", "copy", "-frames:v", "1", destination],
      stderr_to_stdout: true
    )
  rescue
    error in ErlangError ->
      Logger.warning(fn -> "ffmpeg unavailable: #{inspect(error)}" end)
      {"ffmpeg unavailable", 1}
  end

  @doc """
  Whether a string is plausibly an image URL, cheaply where possible.
  """
  def valid_url?(string) when is_binary(string) do
    case URI.new(string) do
      {:ok, %{scheme: scheme} = uri} when is_binary(scheme) ->
        image_mime?(MIME.from_path(string)) or head_says_image?(uri)

      _term ->
        false
    end
  end

  def valid_url?(_term), do: false

  @doc false
  def head_says_image?(uri) do
    case Req.head(url: uri, headers: [{"user-agent", user_agent()}]) do
      {:ok, response} ->
        case Req.Response.get_header(response, "content-type") do
          [mime | _rest] -> image_mime?(mime)
          [] -> false
        end

      _else ->
        false
    end
  end

  def image_mime?("image/" <> _rest), do: true
  def image_mime?(_mime), do: false

  @doc """
  A fresh uploads filename for a mime type.
  """
  def generate_filename(mime) do
    [ext | _rest] = MIME.extensions(mime)
    "#{Ecto.UUID.generate()}.#{ext}"
  end

  @doc "The web path an uploaded image is served from."
  def web_path(filename), do: "/uploads/images/#{filename}"

  defp user_agent, do: Ambry.Utils.http_user_agent()
end
