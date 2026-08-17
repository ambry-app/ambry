defmodule Ambry.Media.Relink.Console do
  @moduledoc """
  Driving the back-catalogue reclaim from a console.

  `Ambry.Media.Relink` knows how to plan and how to relink one recording. This
  is how an operator runs it over four hundred of them: it selects a batch,
  prints what each recording is and what would happen to it, and — only when
  told twice — does it.

  Deliberately not a mix task: a release has no Mix. This runs anywhere the
  application is running, which in production means `bin/ambry remote`.

  ## The three commands

      # read-only, whatever the batch
      Console.report(era: :server_import)

      # the same thing, phrased as the run it isn't yet
      Console.run(era: :server_import, limit: 10)

      # the run
      Console.run(era: :server_import, limit: 10, dry_run: false)

  `run/1` **dry-runs by default**, and the only way to write anything is to say
  `dry_run: false` out loud. A batch tool whose default is to act is a batch
  tool that acts on a typo.

  ## Options

    * `:era` — `:server_import`, `:web_upload` or `:recorded_list`, per
      `Relink.era/1`. The eras want doing in order: the server-import era
      hardlinks within one filesystem, moves no bytes and deletes nothing,
      which makes it the right place to find out what this gets wrong.
    * `:ids` — specific recordings, by id. Named rather than filtered: a
      recording that is not a candidate still gets planned, so it says why
      instead of quietly not appearing.
    * `:limit` — how many, oldest first. Batches are how you stay able to stop.
    * `:dry_run` — `run/1` only, `true` unless you say otherwise.
    * `:stop_on_error` — `run/1` only, `true` by default. A *refusal* is a
      normal outcome and never stops anything: two of the library's recordings
      have no sources left and are supposed to be reported and skipped. An
      *error* is the tool being wrong about the world, and finding that out
      four hundred times in a row is not more information than finding it out
      once.

  ## What it costs

  Every plan probes every source file, and probing decode-counts VBR mp3s,
  which most of a back catalogue is. Measured over the 437-recording
  production library: **~14s per recording, about an hour for all of them.**
  Start it and walk away — and prefer `:limit` to heroism.

  A real run pays that twice, once to plan and once to scan what it placed.
  That is the check that the placed bytes are the bytes.
  """

  alias Ambry.Media.Media
  alias Ambry.Media.Relink
  alias Ambry.Repo

  @doc """
  Plans a batch and prints it. Writes nothing, ever.

  Returns a summary map, so a long report can be read at the end as well as
  watched going past.
  """
  def report(opts \\ []) do
    media_list = select(opts)

    heading("Planning #{length(media_list)} recording(s) — about #{estimate(media_list)}.")

    media_list
    |> Enum.map(fn media ->
      plan = Relink.plan(media)
      print_plan(plan)
      plan
    end)
    |> summarize_plans()
    |> tap(&print_plan_summary/1)
  end

  @doc """
  Relinks a batch — or, by default, says what relinking it would do.

  With `dry_run: false` this places files and writes to the database, one
  recording at a time, printing each outcome as it happens rather than at the
  end. Nothing is deleted and nothing is published either way; see
  `Relink.relink/1`.
  """
  def run(opts \\ []) do
    if Keyword.get(opts, :dry_run, true) do
      opts
      |> report()
      |> tap(fn _summary ->
        IO.puts("Nothing was written. Pass dry_run: false to actually do it.\n")
      end)
    else
      perform(opts)
    end
  end

  defp perform(opts) do
    media_list = select(opts)
    stop_on_error? = Keyword.get(opts, :stop_on_error, true)

    heading("Relinking #{length(media_list)} recording(s) — about #{estimate(media_list)}.")

    media_list
    |> Enum.reduce_while([], fn media, results ->
      result = relink_and_print(media)

      if stop_on_error? and match?({:failed, _id, _reason}, result) do
        heading("Stopped at the first error. Pass stop_on_error: false to carry on regardless.")
        {:halt, [result | results]}
      else
        {:cont, [result | results]}
      end
    end)
    |> Enum.reverse()
    |> summarize_results()
    |> tap(&print_run_summary/1)
  end

  defp relink_and_print(media) do
    case Relink.relink(media) do
      {:ok, media, plan} ->
        print_title(plan.media_id, plan.title)

        detail(
          "relinked: #{length(media.media_tracks)} track(s), #{plan.policy}, " <>
            "#{fmt(plan.probed_duration)}"
        )

        print_paths(media.source_files)

        {:relinked, media.id, plan}

      {:error, %Relink.Plan{} = plan} ->
        print_plan(plan)
        {:refused, plan.media_id, plan}

      {:error, reason} ->
        print_title(media.id, title(media))
        detail("FAILED: #{inspect(reason)}")
        {:failed, media.id, reason}
    end
  end

  # ==========================================================================
  # Selecting a batch
  # ==========================================================================

  defp select(opts) do
    opts
    |> Keyword.get(:ids)
    |> case do
      nil -> Relink.candidates()
      ids -> named(ids)
    end
    |> filter_era(opts[:era])
    |> limit(opts[:limit])
  end

  # Named ids skip the candidate query entirely: asking about a recording that
  # already has tracks should answer "it already has tracks", not answer
  # nothing at all.
  defp named(ids) do
    Enum.flat_map(ids, fn id ->
      case Repo.get(Media, id) do
        nil ->
          heading("[#{id}] no such recording")
          []

        media ->
          [media]
      end
    end)
  end

  defp filter_era(media_list, nil), do: media_list
  defp filter_era(media_list, era), do: Enum.filter(media_list, &(Relink.era(&1) == era))

  defp limit(media_list, nil), do: media_list
  defp limit(media_list, count), do: Enum.take(media_list, count)

  # ==========================================================================
  # Printing
  # ==========================================================================

  defp print_plan(%Relink.Plan{} = plan) do
    print_title(plan.media_id, plan.title)

    detail(
      "era=#{plan.era} files=#{length(plan.sources)} " <>
        "policy=#{plan.policy || "-"} verdict=#{plan.verdict}"
    )

    if plan.stored_duration do
      detail(
        "stored=#{fmt(plan.stored_duration)} probed=#{fmt(plan.probed_duration)} " <>
          "drift=#{fmt(plan.drift, :signed)} tol=#{fmt(plan.tolerance)}"
      )
    end

    Enum.each(plan.problems, &detail("! #{&1}"))
    print_paths(destinations(plan))
  end

  # A 63-file recording is 63 identical lines that differ in their last three
  # digits, and a whole-library report is four hundred of those. The count is
  # the part worth reading, so the tail is summarized rather than dropped
  # quietly — a truncation nobody is told about reads as completeness.
  @shown_paths 3

  defp print_paths(paths) do
    paths |> Enum.take(@shown_paths) |> Enum.each(&detail("-> #{&1}"))

    case length(paths) - @shown_paths do
      more when more > 0 -> detail("-> … and #{more} more")
      _all_shown -> :ok
    end
  end

  # Root-relative, because the root prefix is the same on every line and the
  # part that differs is the part being checked.
  defp destinations(%Relink.Plan{root: nil}), do: []

  defp destinations(%Relink.Plan{root: root, destinations: destinations}),
    do: Enum.map(destinations || [], &Path.relative_to(&1, root.path))

  defp print_title(id, title), do: IO.puts("[#{id}] #{title}")
  defp detail(line), do: IO.puts("      #{line}")
  defp heading(line), do: IO.puts("\n#{line}\n")

  defp print_plan_summary(summary) do
    heading(
      "#{summary.planned} planned: #{summary.ok} ok, #{summary.refused} refused" <>
        policies(summary.policies) <> refusals(summary.refused_ids)
    )
  end

  defp print_run_summary(summary) do
    heading(
      "#{summary.relinked} relinked, #{summary.refused} refused, #{summary.failed} failed" <>
        policies(summary.policies) <> refusals(summary.refused_ids)
    )
  end

  # The ids, not just the count: a refusal is something to go and look at, and
  # scrolling back through four hundred plans to find which two they were is
  # not looking at it.
  defp refusals([]), do: ""
  defp refusals(ids), do: "\nrefused: #{inspect(ids)}"

  defp policies(counts) when counts == %{}, do: ""

  defp policies(counts),
    do: " — " <> Enum.map_join(counts, ", ", fn {policy, count} -> "#{policy} #{count}" end)

  # ==========================================================================
  # Summaries
  # ==========================================================================

  defp summarize_plans(plans) do
    {ok, refused} = Enum.split_with(plans, &(&1.verdict == :ok))

    %{
      planned: length(plans),
      ok: length(ok),
      refused: length(refused),
      policies: count_policies(ok),
      refused_ids: Enum.map(refused, & &1.media_id)
    }
  end

  defp summarize_results(results) do
    relinked = for {:relinked, _id, plan} <- results, do: plan

    %{
      relinked: length(relinked),
      refused: Enum.count(results, &match?({:refused, _id, _plan}, &1)),
      failed: Enum.count(results, &match?({:failed, _id, _reason}, &1)),
      policies: count_policies(relinked),
      refused_ids: for({:refused, id, _plan} <- results, do: id),
      failures: for({:failed, id, reason} <- results, do: {id, reason})
    }
  end

  defp count_policies(plans) do
    plans
    |> Enum.map(& &1.policy)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  # ==========================================================================
  # Plumbing
  # ==========================================================================

  # 14s a recording, measured over the production library, and almost all of
  # it decode-counting VBR mp3s.
  defp estimate(media_list) do
    case div(length(media_list) * 14, 60) do
      0 -> "a minute"
      minutes when minutes < 90 -> "#{minutes} minutes"
      minutes -> "#{Float.round(minutes / 60, 1)} hours"
    end
  end

  defp title(%Media{} = media) do
    case Repo.preload(media, :book) do
      %Media{book: nil} -> "(no book)"
      %Media{} = media -> Media.display_title(media)
    end
  end

  defp fmt(nil), do: "unknown"
  defp fmt(%Decimal{} = decimal), do: fmt(Decimal.to_float(decimal))
  defp fmt(seconds) when is_number(seconds), do: "#{Float.round(seconds / 1, 2)}s"

  defp fmt(seconds, :signed) when is_number(seconds),
    do: "#{if seconds >= 0, do: "+"}#{Float.round(seconds / 1, 2)}s"

  defp fmt(nil, :signed), do: "unknown"
end
