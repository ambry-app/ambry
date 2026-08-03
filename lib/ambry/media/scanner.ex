defmodule Ambry.Media.Scanner do
  @moduledoc """
  Scans a media's source files and records what they are, instead of
  transcoding them into something else.

  This is the direct-play import step: the files are probed, never copied,
  rewritten, or repackaged, and what comes back is written as the media's
  ordered `media_tracks` plus a total duration for the book timeline.

  Scanning does not publish: a scanned media keeps whatever status it had, so
  this can run over the existing library without changing what clients see.
  Only the inbox approval flow (Phase 3) makes a direct-play media `ready`.

  Direct-play v1 handles single-file recordings only. A folder of 40 mp3s is
  reported as `{:error, :multi_file_unsupported}` rather than silently
  concatenated — the tracks model is ready for it, the player isn't (see the
  roadmap's 2f).
  """

  alias Ambry.Media, as: MediaContext
  alias Ambry.Media.Media
  alias Ambry.Media.Scanner.Probe

  @extensions ~w(.mp3 .mp4 .m4a .m4b .flac .ogg .opus .wav)

  @doc """
  Scans a media's source files, replacing its tracks with what's on disk.

  Returns `{:ok, media}` with the updated media, or `{:error, reason}`.
  """
  def scan(%Media{} = media) do
    with {:ok, path} <- single_file(media),
         {:ok, probe} <- Probe.run(path, single_file: true) do
      write_tracks(media, probe)
    end
  end

  @doc """
  Reads a media's embedded tags without writing anything.

  This is the tags-first half of discovery: what the file claims about
  itself, for 1g auto-match to turn into a pre-filled inbox item. Nothing
  here is applied to any record — tags propose, the operator confirms.

  Returns `{:ok, %Tags{}}` or `{:error, reason}`.
  """
  def tags(%Media{} = media) do
    with {:ok, path} <- single_file(media),
         {:ok, probe} <- Probe.run(path, single_file: true) do
      {:ok, probe.tags}
    end
  end

  @doc """
  Probes a single file by path, without a media record.

  This is what the inbox uses: a candidate is measured before anything about
  it exists in the library.
  """
  defdelegate probe_file(path, opts \\ []), to: Probe, as: :run

  @doc """
  The audio file extensions direct-play can serve.
  """
  def extensions, do: @extensions

  # v1 is single-file; the tracks model is multi-file-shaped for later.
  defp single_file(media) do
    case files(media) do
      [file] -> {:ok, file}
      [] -> {:error, :no_audio_files}
      [_ | _] -> {:error, :multi_file_unsupported}
    end
  end

  # `Media.files/2` yields names relative to the source folder for media that
  # recorded `source_files`, and absolute paths for the older ones that
  # didn't.
  defp files(media) do
    media
    |> Media.files(@extensions)
    |> Enum.map(fn file ->
      if Path.type(file) == :absolute, do: file, else: Media.source_path(media, file)
    end)
  end

  defp write_tracks(media, %Probe{} = probe) do
    attrs =
      %{
        media_tracks: [track_attrs(probe)],
        duration: probe.duration
      }
      |> maybe_put_chapters(media, probe)

    MediaContext.update_media(media, attrs)
  end

  defp track_attrs(%Probe{} = probe) do
    %{
      index: 0,
      path: probe.path,
      size: probe.size,
      mime: probe.mime,
      format: probe.format,
      codec: probe.codec,
      duration: probe.duration,
      # single-track v1: the file *is* the whole book timeline
      start_offset: 0,
      seek_accuracy: probe.seek_accuracy
    }
  end

  # Embedded markers are only offered to a media that has none. Chapters are
  # curated data, and the merge that pours provider titles onto file-derived
  # markers is its own piece of work (the roadmap's 1h) — until it exists,
  # scanning must never overwrite what an operator has already confirmed.
  defp maybe_put_chapters(attrs, %Media{chapters: []}, %Probe{chapters: [_ | _] = chapters}) do
    Map.put(attrs, :chapters, chapters)
  end

  defp maybe_put_chapters(attrs, _media, _probe), do: attrs
end
