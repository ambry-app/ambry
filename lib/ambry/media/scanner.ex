defmodule Ambry.Media.Scanner do
  @moduledoc """
  Measures audio files.

  Files are probed, never copied, rewritten or repackaged, and what comes
  back is what a recording is made of: ordered `media_tracks` attributes, a
  total duration for the book timeline, the chapter markers the files carry
  and the tags they claim.

  Nothing here writes to a recording. `Ambry.Inbox.Importer` is what turns
  probes into a recording — on an import and on a replacement alike — and
  this module is the arithmetic it shares with the inbox, which measures the
  same files before anything about them exists in the library.

  ## Multi-file recordings

  A folder of 40 mp3s is 40 tracks laid end to end on one continuous book
  timeline, not a concat job: each file keeps its own bytes and its own
  `start_offset`, and everything downstream — progress, chapters, sync —
  already speaks absolute book-seconds. Nothing is decoded or rewritten here
  either way.

  Order is the order the caller passes, which is discovery's order,
  natural-sorted: `Disc 2` after `Disc 1`, `track10.mp3` after `track2.mp3`
  — the order the operator is shown. Embedded track-number tags are
  deliberately *not* consulted: a visible filename the operator can check
  beats a tag they can't, and the ordering has to be one they can predict
  from the folder.

  ## Tags describe the release, not each file

  A multi-file release's title lives in `album`; `title` is the individual
  file's own name ("Chapter 3"). So tags are read from the first file with
  `single_file: false`, which is what makes `album` win — see the measured
  finding in the roadmap's 1b.
  """

  alias Ambry.Media.Chapters.FromFiles
  alias Ambry.Media.Media
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Scanner.Probe

  @extensions ~w(.mp3 .mp4 .m4a .m4b .flac .ogg .opus .wav)

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

  Two kinds of recording answer this two different ways. An **imported**
  one is made of its tracks, which is what clients are served. A
  **transcoded** one is made of the sources it was transcoded from
  (`Media.files/2`): its packaged artifacts carry no tags, so they are no
  use to anything that reads a file to learn about the recording.

  The tracks are asked first, since an imported recording has no transcode
  sources at all.
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
end
