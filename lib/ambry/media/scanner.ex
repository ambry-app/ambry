defmodule Ambry.Media.Scanner do
  @moduledoc """
  Measures audio files: ordered `media_tracks` attributes, a total duration,
  the chapter markers the files carry and the tags they claim. Files are
  probed, never copied, rewritten or repackaged.

  Nothing here writes to a recording — `Ambry.Inbox.Importer` does that. This
  is the arithmetic it shares with the inbox, which measures the same files
  before anything about them exists in the library.

  ## Multi-file recordings

  A folder of 40 mp3s is 40 tracks laid end to end on one continuous book
  timeline, each keeping its own bytes and its own `start_offset`.

  Order is the caller's, which is discovery's natural sort: `Disc 2` after
  `Disc 1`, `track10.mp3` after `track2.mp3`. Embedded track-number tags are
  deliberately not consulted — the ordering has to be one the operator can
  predict from the folder.

  ## Tags describe the release, not each file

  A multi-file release's title lives in `album`; `title` is the individual
  file's own name ("Chapter 3"). So tags are read from the first file with
  `single_file: false`, which is what makes `album` win.
  """

  alias Ambry.Media.Chapters.FromFiles
  alias Ambry.Media.Media
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Scanner.Probe

  @extensions ~w(.mp3 .mp4 .m4a .m4b .flac .ogg .opus .wav)

  @doc """
  Reads a media's embedded tags without writing anything.

  One ffprobe of a header, not the decode-count a VBR mp3 needs: this runs
  while an edit form is being looked at.

  Returns `{:ok, %Tags{}}` or `{:error, reason}`.
  """
  def tags(%Media{} = media) do
    with {:ok, [first | rest]} <- audio_files(media) do
      Probe.tags(first, single_file: rest == [])
    end
  end

  @doc """
  Probes a single file by path, without a media record.
  """
  defdelegate probe_file(path, opts \\ []), to: Probe, as: :run

  @doc """
  The audio file extensions direct-play can serve.
  """
  def extensions, do: @extensions

  @doc """
  The audio files a media is made of, in play order.

  An imported recording is made of its tracks; a transcoded one of the
  sources it was transcoded from, since its packaged artifacts carry no tags.
  Tracks are asked first.
  """
  # **Pass a media with its tracks loaded.** An unloaded association matches
  # neither clause head and falls through to the transcode sources, which for
  # an imported recording finds nothing. Indistinguishable here, so the
  # invariant lives at `get_media!/1` and `fetch_media/1`.
  def audio_files(%Media{media_tracks: [_ | _] = tracks}) do
    {:ok, tracks |> Enum.sort_by(& &1.index) |> Enum.map(&MediaTrack.disk_path!/1)}
  end

  def audio_files(%Media{} = media) do
    case files(media) do
      [] -> {:error, :no_audio_files}
      files -> {:ok, files}
    end
  end

  # The sort matters for media without recorded `source_files`: `File.ls/1`
  # returns whatever order the filesystem felt like.
  defp files(media) do
    media
    |> Media.files(@extensions)
    |> Enum.sort(NaturalOrder)
  end

  @doc """
  Probes every file of a recording, in play order.

  All of them or none: one unreadable file means every track after it sits at
  the wrong offset.
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

  @doc """
  Track attributes for a list of probes, in play order.

  Each track starts where the previous ended, so the book timeline is
  continuous.
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
  The chapter markers a set of probes offers, as `{chapters, marker_source}`.

  See `Ambry.Media.Chapters.FromFiles`; markers only ever come from files.
  """
  def chapters(probes), do: FromFiles.extract(probes, track_attrs(probes))

  @doc """
  The whole book's duration: every track's, added up.
  """
  def total_duration(probes) do
    Enum.reduce(probes, Decimal.new(0), &Decimal.add(&2, &1.duration))
  end
end
