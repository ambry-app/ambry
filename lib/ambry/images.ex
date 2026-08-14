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
  file inside a library root. That distinction is what makes these safe to
  delete with a record unconditionally.
  """

  import Ambry.Paths

  require Logger

  @doc """
  Downloads an image and returns its web path.
  """
  def import_url(nil), do: {:ok, :no_image_url}
  def import_url(""), do: {:ok, :no_image_url}

  def import_url(url) do
    if valid_url?(url), do: download(url), else: {:error, :invalid_image_url}
  end

  # The bytes decide, for the same reason they decide in `browser_safe/1`:
  # this used to accept only a `content-type` header in an allowlist, and
  # Hardcover's CDN labels every asset `application/octet-stream`. A PNG the
  # operator picked from the person picker therefore passed `valid_url?` on
  # its extension and then failed the download — silently, since a failed
  # cover import is not fatal to an import. Sniffing the body means the
  # preview and the import agree, and the file lands with the extension its
  # bytes earn rather than the one its header claimed.
  defp download(url) do
    with {:ok, %{status: 200, body: body}} when is_binary(body) <-
           Req.get(url: url, headers: [{"user-agent", user_agent()}], decode_body: false),
         {:ok, image, mime} <- browser_safe(body) do
      filename = generate_filename(mime)
      File.write!(images_disk_path(filename), image)

      {:ok, web_path(filename)}
    else
      _term -> {:error, :failed_to_download_image}
    end
  end

  @doc """
  Extracts an audio file's embedded cover art and returns its web path.

  Cover art rides along as an `attached_pic` video stream, so pulling it out
  is a stream copy rather than a re-encode: `-c:v copy` keeps the publisher's
  original bytes rather than generationally re-compressing them.

  What it does NOT do any more is assume those bytes are a JPEG. This wrote
  `generate_filename("image/jpeg")` and then stream-copied whatever was in
  there into it, so the operator's Martian — a big-endian TIFF in a stream the
  container calls PNG — was imported as 753KB of TIFF in a file named `.jpg`.
  Firefox's verdict, accurately: "the jpeg contains errors". The thumbnails
  were fine the whole time, because libvips reads by content and ignores the
  name; only the original, which is what the form renders, was a lie.

  So the bytes decide the format and the extension, and anything a browser
  can't show is re-encoded on the way in. That is `read_embedded/1`'s job
  exactly, and this is now that plus a file: one extraction path, one policy
  about what a servable image is.
  """
  def extract_embedded(audio_path) do
    with {:ok, binary, mime} <- read_embedded(audio_path) do
      filename = generate_filename(mime)
      File.write!(images_disk_path(filename), binary)
      {:ok, web_path(filename)}
    end
  end

  @doc """
  Reads an audio file's embedded cover art into memory.

  `extract_embedded/1` writes into the uploads directory because its caller is
  importing. A *preview* must not: looking at an inbox item you then dismiss
  would leave an orphaned image behind every time.
  """
  def read_embedded(audio_path) do
    destination = Path.join(System.tmp_dir!(), "ambry-cover-#{Ecto.UUID.generate()}")

    try do
      with {_output, 0} <- ffmpeg(audio_path, destination, ["-f", "image2"]),
           {:ok, binary} <- File.read(destination) do
        browser_safe(binary)
      else
        _no_image -> {:error, :no_embedded_image}
      end
    after
      File.rm(destination)
    end
  end

  @doc """
  Image bytes a browser will actually render, and the mime type to serve them
  under.

  The attached picture keeps its original encoding under `-c:v copy`, so the
  bytes say what it is and the filename can't. What they say is not
  necessarily what the *container* says: the operator's Martian declares a PNG
  stream and carries a big-endian TIFF (`4D 4D 00 2A`), which ffprobe itself
  complains about ("Invalid PNG signature"). The picture extracted fine,
  failed the sniff, and the preview 404'd into a broken image sitting next to
  a chip offering it — for the one decision where seeing the art is the entire
  point.

  So anything libvips can read becomes a JPEG rather than a 404. Passing
  unrecognized bytes straight through would only move the broken image: a
  browser can't show a TIFF either.
  """
  def browser_safe(binary) do
    case sniff(binary) do
      {:ok, mime} -> {:ok, binary, mime}
      :error -> transcode(binary)
    end
  end

  defp transcode(binary) do
    with {:ok, image} <- Image.from_binary(binary),
         {:ok, jpeg} <- Image.write(image, :memory, suffix: ".jpg", quality: 90) do
      {:ok, jpeg, "image/jpeg"}
    else
      _unreadable -> {:error, :no_embedded_image}
    end
  end

  defp sniff(<<0xFF, 0xD8, _rest::binary>>), do: {:ok, "image/jpeg"}
  defp sniff(<<0x89, "PNG\r\n", 0x1A, "\n", _rest::binary>>), do: {:ok, "image/png"}
  defp sniff("GIF8" <> _rest), do: {:ok, "image/gif"}
  defp sniff(<<"RIFF", _size::binary-4, "WEBP", _rest::binary>>), do: {:ok, "image/webp"}
  defp sniff(_other), do: :error

  defp ffmpeg(source, destination, extra) do
    System.cmd(
      "ffmpeg",
      ["-nostdin", "-y", "-i", source, "-an", "-c:v", "copy", "-frames:v", "1"] ++
        extra ++ [destination],
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
