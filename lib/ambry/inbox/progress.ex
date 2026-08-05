defmodule Ambry.Inbox.Progress do
  @moduledoc """
  What is happening to an inbox item right now.

  Everything the inbox does to an item happens in a background job, and until
  now a row gave no sign of whether its jobs were queued, running, finished
  or failed. "Why is this row blank?" and "did my scan actually run?" had no
  answer short of opening the Oban dashboard.

  ## Absence of a job does not mean done

  The Oban pruner deletes jobs older than a day, so the job table can only
  ever answer for recent work. A row from last week has no jobs at all and is
  perfectly fine. So the status is derived in two steps: if a job exists, its
  state wins; if none does, the item's own contents say whether the work ever
  happened.

  That fallback is the whole reason this isn't a two-line query.

  ## Failures outlive their jobs

  A failure is visible for a day and then gone forever, so anything worth
  telling the operator about tomorrow is written onto the item's `issue`
  instead, and that's what the `:issue` status reflects.

  ## Retrying is not the same as queued

  Matching retries with a backoff measured in minutes, because the shared
  metadata instances rate-limit with a ~30s `Retry-After` and spending the
  immediate retry on being told no again is waste. An item mid-backoff looks
  exactly like one that was never matched — blank — so `:retrying` is its own
  status rather than being folded into `:queued`.
  """

  import Ecto.Query

  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.RunMatch
  alias Ambry.Inbox.RunProbe
  alias Ambry.Repo

  @workers [RunProbe, RunMatch]

  @doc """
  The status of each given item, as a map of item id to status.

  One query for the whole page rather than one per row.

  Statuses:

    * `:working` — a job is executing right now
    * `:retrying` — a job failed and is waiting to try again
    * `:queued` — a job is waiting to run
    * `:failed` — a job gave up, and recently enough to still be in the table
    * `:issue` — the item itself records a problem, which outlives the job
    * `:done` — probed and matched; ready for the operator to decide on
    * `:incomplete` — probed, but never matched, and nothing is queued
    * `:never_ran` — no probe, no job; something went wrong long ago
  """
  def statuses(items) when is_list(items) do
    jobs = job_states(Enum.map(items, & &1.id))
    Map.new(items, &{&1.id, status(&1, Map.get(jobs, &1.id, []))})
  end

  @doc """
  The status of a single item.
  """
  def status(%InboxItem{} = item) do
    status(item, Map.get(job_states([item.id]), item.id, []))
  end

  defp status(%InboxItem{} = item, states) do
    cond do
      "executing" in states -> :working
      "retryable" in states -> :retrying
      Enum.any?(states, &(&1 in ~w(available scheduled))) -> :queued
      Enum.any?(states, &(&1 in ~w(discarded cancelled))) -> :failed
      item.issue -> :issue
      is_nil(item.probe) -> :never_ran
      is_nil(item.matches) -> :incomplete
      true -> :done
    end
  end

  # Oban stores args as jsonb, so the item id is queryable without any new
  # writes and without a job↔record association that would have to be kept
  # in step.
  defp job_states([]), do: %{}

  defp job_states(item_ids) do
    ids = Enum.map(item_ids, &to_string/1)

    from(j in "oban_jobs",
      where: j.worker in ^Enum.map(@workers, &worker_name/1),
      where: fragment("?->>'inbox_item_id'", j.args) in ^ids,
      select: {fragment("?->>'inbox_item_id'", j.args), j.state}
    )
    |> Repo.all()
    |> Enum.group_by(fn {id, _state} -> String.to_integer(id) end, fn {_id, state} -> state end)
  end

  defp worker_name(module), do: module |> to_string() |> String.replace_prefix("Elixir.", "")
end
