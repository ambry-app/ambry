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

  ## Multi-file recordings

  A folder of 40 mp3s is 40 tracks laid end to end on one continuous book
  timeline, not a concat job: each file keeps its own bytes and its own
  `start_offset`, and everything downstream — progress, chapters, sync —
  already speaks absolute book-seconds. Nothing is decoded or rewritten here
  either way.

  Order is the order `Media.files/2` yields, natural-sorted: `Disc 2` after
  `Disc 1`, `track10.mp3` after `track2.mp3`. That is the same order
  discovery recorded the files in, so an inbox import re-derives exactly what
  the operator was shown. Embedded track-number tags are deliberately *not*
  consulted — a visible filename the operator can check beats a tag they
  can't, and the ordering has to be one they can predict from the folder.

  ## Tags describe the release, not each file

  A multi-file release's title lives in `album`; `title` is the individual
  file's own name ("Chapter 3"). So tags are read from the first file with
  `single_file: false`, which is what makes `album` win — see the measured
  finding in the roadmap's 1b.
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
    with {:ok, paths} <- audio_files(media),
         {:ok, probes} <- probe_all(paths) do
      write_tracks(media, probes)
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
    with {:ok, [first | rest]} <- audio_files(media),
         {:ok, probe} <- Probe.run(first, single_file: rest == []) do
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

  @doc """
  The audio files a media is made of, in play order.

  Public because placement and organization have to move the same files in
  the same order this writes tracks in.
  """
  def audio_files(%Media{} = media) do
    case files(media) do
      [] -> {:error, :no_audio_files}
      files -> {:ok, files}
    end
  end

  # `Media.files/2` yields names relative to the source folder for media that
  # recorded `source_files`, and absolute paths for the older ones that
  # didn't. The sort matters for the second kind: `File.ls/1` returns
  # whatever order the filesystem felt like, which for a 40-file book is a
  # shuffled audiobook.
  defp files(media) do
    media
    |> Media.files(@extensions)
    |> Enum.map(fn file ->
      if Path.type(file) == :absolute, do: file, else: Media.source_path(media, file)
    end)
    |> Enum.sort(NaturalOrder)
  end

  @doc """
  Probes every file of a recording, in play order.

  All of them or none: one unreadable file in forty means every track after
  it sits at the wrong offset, so this fails rather than quietly producing a
  book that is short by a chapter.
  """
  def probe_all(paths) do
    single_file = match?([_only], paths)

    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      case Probe.run(path, single_file: single_file) do
        {:ok, probe} -> {:cont, {:ok, [probe | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, probes} -> {:ok, Enum.reverse(probes)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_tracks(media, probes) do
    attrs =
      %{
        media_tracks: track_attrs(probes),
        duration: total_duration(probes)
      }
      |> maybe_put_chapters(media, probes)

    MediaContext.update_media(media, attrs)
  end

  @doc """
  Track attributes for a list of probes, in play order.

  Tracks are laid end to end: each one starts where the previous ended, so
  the book timeline is continuous and absolute book-seconds mean the same
  thing to a one-file m4b and a forty-file mp3 rip.

  Public because the inbox importer writes a recording's first tracks
  straight from its own probes, and two hand-rolled versions of this
  arithmetic is exactly one too many.
  """
  def track_attrs(probes) do
    probes
    |> Enum.with_index()
    |> Enum.map_reduce(Decimal.new(0), fn {probe, index}, offset ->
      attrs = %{
        index: index,
        path: probe.path,
        size: probe.size,
        mime: probe.mime,
        format: probe.format,
        codec: probe.codec,
        duration: probe.duration,
        start_offset: offset,
        seek_accuracy: probe.seek_accuracy
      }

      {attrs, Decimal.add(offset, probe.duration)}
    end)
    |> elem(0)
  end

  @doc """
  The chapter markers a set of probes offers, if any.

  A single file's embedded markers come in with it. A multi-file recording's
  markers are its file boundaries, which is the chapter work's job to write
  with a title source attached (the roadmap's 1h) rather than something to
  take from whichever file happened to be first.
  """
  def embedded_chapters([%Probe{chapters: chapters}]), do: chapters
  def embedded_chapters(_multi_file), do: []

  @doc """
  The whole book's duration: every track's, added up.
  """
  def total_duration(probes) do
    Enum.reduce(probes, Decimal.new(0), &Decimal.add(&2, &1.duration))
  end

  # Embedded markers are only offered to a media that has none. Chapters are
  # curated data, and the merge that pours provider titles onto file-derived
  # markers is its own piece of work (the roadmap's 1h) — until it exists,
  # scanning must never overwrite what an operator has already confirmed.
  defp maybe_put_chapters(attrs, %Media{chapters: []}, probes) do
    case embedded_chapters(probes) do
      [] -> attrs
      chapters -> Map.put(attrs, :chapters, chapters)
    end
  end

  defp maybe_put_chapters(attrs, _media, _probes), do: attrs
end
