defmodule Ambry.Inbox.Progress do
  @moduledoc """
  What is happening to an inbox item right now.

  Everything the inbox does happens in a background job, so without this a row
  gives no sign of whether its jobs are queued, running, finished or failed.

  **Absence of a job does not mean done.** The Oban pruner deletes jobs after
  a day, so a row from last week has none and is perfectly fine. The status is
  derived in two steps: a job's state wins where one exists, and the item's own
  contents say whether the work ever happened where none does.

  **Failures outlive their jobs.** Anything worth telling the operator about
  tomorrow is written onto the item's `issue`, which is what `:issue`
  reflects.

  **Retrying is not queued.** Matching backs off in minutes while a provider
  rate-limits, and an item mid-backoff looks exactly like one that was never
  matched, so it is its own status.
  """

  import Ecto.Query

  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.RunImport
  alias Ambry.Inbox.RunMatch
  alias Ambry.Inbox.RunProbe
  alias Ambry.Repo

  @workers [RunProbe, RunMatch, RunImport]

  @doc """
  Whether a background job currently owns this item.

  Running, waiting to run, and waiting to run *again* all mean the same thing
  to somebody looking at the form: it is not yours yet.

  `:retrying` belongs here because matching keeps going until every provider
  has answered, so an item can sit mid-backoff for minutes and then **rebuild
  its own draft**, throwing away anything typed into it meanwhile.
  """
  def busy?(status), do: status in [:working, :queued, :retrying, :importing]

  @doc """
  The status of each given item, as a map of item id to status. One query for
  the whole page rather than one per row.

    * `:importing` — the item is being added to the library
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

  defp status(%InboxItem{} = item, jobs) do
    states = Enum.map(jobs, &elem(&1, 1))

    cond do
      # Named apart from every other job: it is the one the operator started
      # themselves, and a generic "working on it" over a row they just pressed
      # Add on says nothing about whether the press landed.
      importing?(jobs) -> :importing
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

  # Oban stores args as jsonb, so the item id is queryable without a
  # job-to-record association that would have to be kept in step.
  defp job_states([]), do: %{}

  defp job_states(item_ids) do
    ids = Enum.map(item_ids, &to_string/1)

    from(j in "oban_jobs",
      where: j.worker in ^Enum.map(@workers, &worker_name/1),
      where: fragment("?->>'inbox_item_id'", j.args) in ^ids,
      select: {fragment("?->>'inbox_item_id'", j.args), j.worker, j.state}
    )
    |> Repo.all()
    |> Enum.group_by(
      fn {id, _worker, _state} -> String.to_integer(id) end,
      fn {_id, worker, state} -> {worker, state} end
    )
  end

  defp worker_name(module), do: module |> to_string() |> String.replace_prefix("Elixir.", "")

  @importing_states ~w(available scheduled executing retryable)

  defp importing?(jobs) do
    Enum.any?(jobs, fn {worker, state} ->
      worker == worker_name(RunImport) and state in @importing_states
    end)
  end
end
