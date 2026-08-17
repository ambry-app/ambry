defmodule Ambry.Media.Relink do
  @moduledoc """
  Working out what upgrading a legacy recording to direct play would do.

  A recording imported before direct play existed was transcoded: its audio
  lives twice on disk, once as the files it came from and once as the packaged
  artifact Ambry serves. Relinking points the recording at the originals —
  placed into a library root and scanned into tracks — so the artifact can go.

  **This module only plans. It writes nothing**, which is what makes it safe to
  run against production before anything else exists, one recording at a time,
  and read the answer.

  ## Why a plan is a separate thing from doing it

  Every input here is a guess about the world that can be wrong in a way no
  database constraint can catch. A recorded path can still resolve while
  holding a *different file* than the one that was transcoded — the downloads
  folder is live, and files get replaced, upgraded and re-downloaded in place.
  Relinking that would silently move a recording's audio under saved positions
  and curated chapter markers.

  So the plan carries its evidence and every reason it might be wrong, and
  refuses rather than guessing. An operator reads it; a batch run gates on it.

  ## The two eras, and how the files are found

  Which files a recording came from is recorded differently depending on when
  it was imported, and neither way is a list you can simply trust:

    * **Web-upload era** — `source_files` is empty, because that column
      postdates these rows. The files are whatever audio sits in the
      recording's `source_media/<uuid>/` folder, found by listing it. The
      recorded truth is a *folder*, so anything else in it comes along.
    * **Server-import era** — `legacy_source_files` holds absolute container
      paths, the one column the paths refactor left holding absolutes because
      it is provenance for recordings that predate roots. **Absolute means
      environment-dependent**: they were `/app/local/...` until prod moved to
      a single `/data` mount, and they will be wrong again after any future
      remount.

  A recording with tracks already is not a candidate, and neither is one whose
  files cannot be found at all.

  ## The duration gate

  The one check that catches a path pointing at the wrong file. Sum the probed
  durations of the sources and compare against the recording's stored duration
  — which came from the transcode, so agreement means the files on disk are
  the files that were transcoded.

  The tolerance is **file-count-aware, not flat**. ffmpeg's concat accumulates
  mp3 frame padding per file boundary, so a 63-file recording legitimately
  drifts a few seconds while a single-file one should agree to the microsecond.
  A flat window wide enough for the first is far too wide for the second.

  Surveyed across the whole production back catalogue (435 recordings,
  2026-08-16): **every single one agrees.** Multi-file mp3 sets drift by a
  strikingly consistent ~65ms per boundary — 63 files → 4.10s, 56 → 3.62s,
  28 → 1.72s — and every one lands comfortably inside its tolerance. Nothing
  in the library has a source that is not the file it was transcoded from.

  That makes the gate cheap insurance rather than a filter, which is the right
  thing for it to be: it is what *established* the above, and it is what will
  catch the case whenever the downloads folder does move under a recording.

  Note the drift is the *transcode* being imprecise, not the sources — so the
  relinked timeline is the more accurate one, which is also why stored chapter
  markers on a long multi-file mp3 set can sit a second or two off afterwards.

  **Measure with `Scanner.Probe`, never with `ffprobe -show_format` alone.**
  A VBR mp3 without an index reports a *claimed* duration that can be tens of
  seconds out; `Probe` decode-counts those, which is what the transcode did.
  A first survey using the claimed figure invented two mismatches that do not
  exist.
  """

  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Library
  alias Ambry.Library.NamingTemplate
  alias Ambry.Library.Placement
  alias Ambry.Library.Root
  alias Ambry.Media.Media
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Scanner
  alias Ambry.Repo
  alias Ambry.Settings

  @extensions ~w(.mp3 .mp4 .m4a .m4b .flac .ogg .opus .wav)

  # Per file *boundary*, with headroom: the measured figure is ~65ms and the
  # padding is systematic rather than noisy, so 1.5x covers it without
  # widening far enough to admit a genuinely different file. The floor is what
  # a single-file recording gets.
  @drift_per_boundary_ms 65
  @drift_headroom 1.5
  @minimum_tolerance_seconds 2.0

  defmodule Plan do
    @moduledoc """
    What relinking one recording would do, and every reason it might not.

    `:verdict` is `:ok` only when nothing was found wrong. Everything else is
    reported rather than raised, so a batch can list its refusals instead of
    stopping at the first.
    """

    @enforce_keys [:media_id, :title, :era, :verdict, :problems, :sources]
    defstruct [
      :media_id,
      :title,
      :era,
      :verdict,
      :problems,
      :sources,
      :stored_duration,
      :probed_duration,
      :drift,
      :tolerance,
      :root,
      :policy,
      :destinations
    ]
  end

  @doc """
  Plans the relink of one recording. Reads only.

  Pass a media id or a loaded `Media`. Probing reads each source file's
  header, so this costs an ffprobe per file and no decoding.
  """
  def plan(media_id) when is_integer(media_id) do
    case Repo.get(Media, media_id) do
      nil -> {:error, :not_found}
      media -> plan(media)
    end
  end

  def plan(%Media{} = media) do
    media = preload_for_plan(media)
    era = era(media)
    sources = sources(media, era)

    %Plan{
      media_id: media.id,
      title: title(media),
      era: era,
      sources: sources,
      verdict: :ok,
      problems: []
    }
    |> refuse_if_already_direct_play(media)
    |> refuse_if_sources_missing()
    |> check_duration(media)
    |> propose_destination(media)
    |> settle_verdict()
  end

  @doc """
  Every legacy recording, oldest first — the candidates for relinking.

  A recording is legacy here if it has no tracks. Whether it still has its
  packaged artifacts is a separate question and deliberately not asked: the
  artifacts are what relinking retires, not what qualifies it.
  """
  def candidates do
    tracked = from(t in MediaTrack, select: t.media_id, distinct: true)

    Media
    |> where([m], m.id not in subquery(tracked))
    |> order_by([m], asc: m.id)
    |> Repo.all()
  end

  @doc """
  Plans every candidate, and groups the results by verdict.

  The whole-library read to do before letting anything run.

  **Budget an hour.** Probing an indexed container is instant, but a VBR mp3
  has to be decode-counted, and most of a back catalogue is mp3. Measured over
  the 437-recording production library: 53 minutes, ~14s per recording. That
  is a console command to start and walk away from, and the reason a version
  of this that runs in a request or a LiveView needs to be an Oban job.
  """
  def survey(media_list \\ nil) do
    (media_list || candidates())
    |> Enum.map(&plan/1)
    |> Enum.group_by(& &1.verdict)
  end

  # ==========================================================================
  # Which files, and where they are
  # ==========================================================================

  # `source_files` is authoritative when a recording has it. The upload era
  # has neither that nor `legacy_source_files`, and its files are found by
  # listing the folder `source_path` names — the same fallback `Media.files/2`
  # has always used for these rows.
  defp era(%Media{legacy_source_files: [_ | _]}), do: :server_import
  defp era(%Media{source_files: [_ | _]}), do: :recorded_list
  defp era(%Media{}), do: :web_upload

  defp sources(%Media{} = media, :server_import) do
    Enum.map(media.legacy_source_files, &source/1)
  end

  defp sources(%Media{} = media, _era) do
    media
    |> Media.files(@extensions)
    |> Enum.map(&source/1)
  end

  defp source(path) do
    %{path: path, exists?: File.regular?(path)}
  end

  # ==========================================================================
  # The checks
  # ==========================================================================

  defp refuse_if_already_direct_play(plan, media) do
    case Repo.aggregate(from(t in MediaTrack, where: t.media_id == ^media.id), :count) do
      0 -> plan
      n -> problem(plan, "already has #{n} track(s); it is not a legacy recording")
    end
  end

  defp refuse_if_sources_missing(%Plan{sources: []} = plan) do
    problem(plan, "no source files found — nothing recorded and nothing on disk")
  end

  defp refuse_if_sources_missing(%Plan{sources: sources} = plan) do
    case Enum.reject(sources, & &1.exists?) do
      [] ->
        plan

      missing ->
        problem(
          plan,
          "#{length(missing)} of #{length(sources)} source file(s) are not on disk: " <>
            (missing |> Enum.take(3) |> Enum.map_join(", ", & &1.path))
        )
    end
  end

  # Skipped when the files aren't all there — probing what is present would
  # produce a total that is short for a known reason and read like a mismatch.
  defp check_duration(%Plan{problems: [_ | _]} = plan, _media), do: plan

  defp check_duration(plan, media) do
    stored = media.duration && seconds(media.duration)
    tolerance = tolerance(length(plan.sources))

    case probe_total(plan.sources) do
      {:ok, probed} ->
        drift = stored && probed - stored

        plan = %{
          plan
          | stored_duration: stored,
            probed_duration: probed,
            drift: drift,
            tolerance: tolerance
        }

        cond do
          is_nil(stored) ->
            problem(plan, "no stored duration to check the sources against")

          abs(drift) > tolerance ->
            problem(
              plan,
              "sources total #{fmt(probed)} against a stored #{fmt(stored)} " <>
                "(#{fmt(drift, :signed)}, tolerance #{fmt(tolerance)}) — " <>
                "the file at the recorded path may not be the file that was transcoded"
            )

          true ->
            plan
        end

      {:error, reason} ->
        problem(%{plan | tolerance: tolerance}, "couldn't probe the sources: #{inspect(reason)}")
    end
  end

  # Probed durations are `Decimal`, as is the stored one; both become floats
  # here because the comparison is a tolerance in seconds, not an exactness
  # question, and a float round-trips a real duration exactly.
  defp probe_total(sources) do
    sources
    |> Enum.map(& &1.path)
    |> Scanner.probe_all()
    |> case do
      {:ok, probes} -> {:ok, Enum.reduce(probes, 0.0, &(seconds(&1.duration) + &2))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp seconds(%Decimal{} = d), do: Decimal.to_float(d)
  defp seconds(n) when is_number(n), do: n / 1

  @doc """
  The duration tolerance for a recording of `count` files, in seconds.

  Exposed because it is the number an operator will want to argue with.
  """
  def tolerance(count) when count <= 1, do: @minimum_tolerance_seconds

  def tolerance(count) do
    max(
      @minimum_tolerance_seconds,
      (count - 1) * @drift_per_boundary_ms * @drift_headroom / 1000
    )
  end

  # ==========================================================================
  # Where it would go
  # ==========================================================================

  # Only computed for a plan that is otherwise sound: rendering a destination
  # for a recording that cannot be relinked invites reading it as an intention.
  defp propose_destination(%Plan{problems: [_ | _]} = plan, _media), do: plan

  defp propose_destination(plan, media) do
    case Library.list_roots() do
      [] ->
        problem(plan, "no library root exists to place into")

      roots ->
        root = Enum.min_by(roots, & &1.id)
        place_into(plan, media, root)
    end
  end

  defp place_into(plan, media, %Root{} = root) do
    values = Books.naming_values(media.book, media)

    with {:ok, folder} <- NamingTemplate.render(Settings.library_naming_template(), values),
         {:ok, filenames} <-
           NamingTemplate.filenames(values, Enum.map(plan.sources, & &1.path), recording(media)),
         {:ok, policy} <- policy(plan.sources, root) do
      destinations = Enum.map(filenames, &Path.join([root.path, folder, &1]))

      %{plan | root: root, policy: policy, destinations: destinations}
    else
      {:error, {:undecidable_policy, reason}} ->
        problem(
          %{plan | root: root},
          "couldn't tell whether the sources and the root share a filesystem: " <>
            "#{inspect(reason)} — the root's volume is probably not mounted"
        )

      {:error, reason} ->
        problem(plan, "couldn't render a destination name: #{inspect(reason)}")
    end
  end

  # Hardlink where the sources and the root share a filesystem, which is the
  # whole point — no bytes move, and the recording simply gains a second name
  # for them.
  #
  # Otherwise **copy, deliberately, and not move**. A move is place-then-delete
  # and the delete is what makes a relink one-way: the upload-era originals in
  # `source_media` are the only copy those recordings have.
  #
  # Note what the two policies actually differ on. The destination gains the
  # same bytes either way — the copy has to land there regardless — so its free
  # space says nothing about which to pick. The *only* difference is whether
  # the originals on the other NAS are deleted now or later, and deleting them
  # now buys back space on a volume that is not short of it while spending the
  # last copy before anything has been heard.
  #
  # So the reclaim happens in two deliberate acts. This one adds a copy and is
  # reversible by deleting it. Emptying `source_media` is a later pass over
  # recordings that have already been verified playing, and it is the one that
  # cannot be undone — which is exactly why it should not be a side effect of
  # this one.
  #
  # **`hardlinkable?/2` answers `{:ok, boolean}` or `{:error, reason}` despite
  # the name**, and the error is what an unmounted root looks like —
  # `Library.device/1` is deliberately strict about the path existing, because
  # walking up to an existing ancestor would report the OS disk's device for a
  # path on an unmounted volume. Treating that tuple as a truthy boolean
  # proposes a hardlink for a destination nothing can even stat, which is the
  # oldest rule here: a call that failed and a call that found nothing must
  # never look the same. So it refuses instead.
  defp policy([%{path: path} | _], %Root{path: root_path}) do
    case Placement.hardlinkable?(path, root_path) do
      {:ok, true} -> {:ok, :hardlink}
      {:ok, false} -> {:ok, :copy}
      {:error, reason} -> {:error, {:undecidable_policy, reason}}
    end
  end

  defp policy([], _root), do: {:ok, nil}

  defp recording(media) do
    %{part: part(media), token: Media.filename_token(media)}
  end

  defp part(%Media{part_number: nil}), do: nil

  defp part(%Media{part_number: number, recording_group: group}) do
    %{number: number, total: group && group.parts_total, word: group && group.part_word}
  end

  # ==========================================================================
  # Plumbing
  # ==========================================================================

  defp preload_for_plan(media) do
    Repo.preload(
      media,
      [
        :library_root,
        :recording_group,
        {:media_narrators, :narrator},
        {:book, [{:book_authors, :author}, {:series_books, :series}]}
      ],
      force: true
    )
  end

  defp title(%Media{book: book} = media) when not is_nil(book), do: Media.display_title(media)
  defp title(%Media{}), do: "(no book)"

  defp problem(plan, message), do: %{plan | problems: plan.problems ++ [message]}

  defp settle_verdict(%Plan{problems: []} = plan), do: %{plan | verdict: :ok}
  defp settle_verdict(plan), do: %{plan | verdict: :refused}

  defp fmt(seconds, :signed) when is_number(seconds),
    do: "#{if seconds >= 0, do: "+"}#{Float.round(seconds / 1, 2)}s"

  defp fmt(nil), do: "unknown"
  defp fmt(seconds), do: "#{Float.round(seconds / 1, 2)}s"
end
