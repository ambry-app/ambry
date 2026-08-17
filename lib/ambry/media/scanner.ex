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

  alias Ambry.Library
  alias Ambry.Media, as: MediaContext
  alias Ambry.Media.Chapters.FromFiles
  alias Ambry.Media.Media
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Scanner.Probe
  alias Ambry.Paths

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

  What the file claims about itself: the tags-first half of discovery, and
  the only evidence a recording imported before the inbox existed carries of
  its own. Nothing here is applied to any record — tags propose, the operator
  confirms.

  Cheap on purpose. It reads the tags rather than probing the file, so it
  costs one ffprobe of a header instead of the decode-count a VBR mp3 needs
  before anyone can trust its duration — this runs while an edit form is
  being looked at, and a fourteen-second answer is not one.

  Returns `{:ok, %Tags{}}` or `{:error, reason}`.
  """
  def tags(%Media{} = media) do
    with {:ok, [first | rest]} <- audio_files(media) do
      Probe.tags(first, single_file: rest == [])
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

  Two different recordings answer this two different ways, and the
  difference is the whole shape of the library right now: an **imported**
  recording is made of its tracks, which is what clients are served; a
  **transcoded** one is made of the sources it was transcoded from
  (`Media.files/2`), because its packaged artifacts are not audio files
  anyone can read tags off — shaka-packager strips them.

  Asking the tracks first is what keeps this honest for an imported
  recording, which has no transcode sources at all.
  """
  def audio_files(%Media{media_tracks: [_ | _] = tracks}) do
    {:ok, tracks |> Enum.sort_by(& &1.index) |> Enum.map(&MediaTrack.disk_path!/1)}
  end

  def audio_files(%Media{} = media) do
    case files(media) do
      [] -> {:error, :no_audio_files}
      files -> {:ok, files}
    end
  end

  # `Media.files/2` resolves to absolute disk paths. The sort matters for
  # media without recorded `source_files`: `File.ls/1` returns whatever
  # order the filesystem felt like, which for a 40-file book is a shuffled
  # audiobook.
  defp files(media) do
    media
    |> Media.files(@extensions)
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

  # Tracks store {root FK, relative path}, never the absolute the probe ran
  # on — a file outside the media's root and the uploads tree has no stored
  # form, and the scan refuses rather than writing an unservable path.
  defp write_tracks(media, probes) do
    with {:ok, tracks} <- stored_tracks(media, probes) do
      attrs =
        %{
          media_tracks: tracks,
          duration: total_duration(probes)
        }
        |> maybe_put_chapters(media, probes)

      MediaContext.update_media(media, attrs)
    end
  end

  defp stored_tracks(media, probes) do
    probes
    |> track_attrs()
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      case stored_track_path(media, attrs.path) do
        {:ok, {root_id, stored}} ->
          attrs = attrs |> Map.put(:path, stored) |> Map.put(:library_root_id, root_id)
          {:cont, {:ok, [attrs | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tracks} -> {:ok, Enum.reverse(tracks)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stored_track_path(%Media{library_root_id: root_id}, absolute) when is_integer(root_id) do
    {:ok, root} = Library.fetch_root(root_id)

    case Library.relativize(root, absolute) do
      {:ok, relative} -> {:ok, {root_id, relative}}
      {:error, :outside_location} -> uploads_stored_form(absolute)
    end
  end

  defp stored_track_path(%Media{}, absolute), do: uploads_stored_form(absolute)

  defp uploads_stored_form(absolute) do
    case Paths.disk_to_web(absolute) do
      "/uploads/" <> _rest = web_path -> {:ok, {nil, web_path}}
      _outside -> {:error, {:outside_library, absolute}}
    end
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
  The chapter markers a set of probes offers, and where they came from.

  Returns `{chapters, marker_source}`. See `Ambry.Media.Chapters.FromFiles` —
  markers only ever come from the files, never from a provider.
  """
  def chapters(probes), do: FromFiles.extract(probes, track_attrs(probes))

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
    case chapters(probes) do
      {[], _source} -> attrs
      {chapters, source} -> Map.merge(attrs, %{chapters: chapters, chapter_marker_source: source})
    end
  end

  defp maybe_put_chapters(attrs, _media, _probes), do: attrs
end
