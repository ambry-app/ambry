defmodule Ambry.Inbox.RunMatch do
  @moduledoc """
  Proposes what one inbox item is.

  Kept to one at a time on purpose. Cold-starting a server from an existing
  collection means hundreds of lookups against shared metadata instances that
  rate-limit — so this trades wall-clock for being a well-behaved client, and
  the queue drains in the background either way. Day to day it's a handful of
  books, where the serialisation costs nothing.

  Because nothing waits on it, matching is allowed to be **thorough**: search
  every enabled provider, fetch full details for the records about the top
  work, and ask every editions-capable database what recordings that work has.

  ## Retries

  A rate-limited provider must not cost an item its records permanently. The
  job backs off and tries again, and the operator can retry a single provider
  from the form besides.

  **The job is not finished until every provider it meant to ask has
  answered.** Retrying only covered a job that *crashed*, and a match where
  one provider was rate-limited does not crash: records get written, a draft
  gets staged, and the job reports success having quietly got less than it set
  out to get. On a cold batch a provider can fail on a third of the items and
  leave one of them with no work candidates at all. So a provider that
  couldn't be reached fails the job, which is what puts it back on the
  queue, and because provider errors are never cached while answers are, each
  attempt keeps what it got and re-asks only what it missed.
  """

  use Oban.Worker,
    queue: :metadata,
    max_attempts: 8,
    unique: [period: 60, fields: [:worker, :args]]

  alias Ambry.Inbox

  require Logger

  # Ten minutes. Long enough to outlast a rate-limit window, short enough that
  # eight attempts still finish inside an hour.
  @max_backoff 600

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"inbox_item_id" => id} = args} = job) do
    case Inbox.fetch_item(id) do
      {:ok, item} ->
        with {:ok, item} <- Inbox.match_item(item, refresh: !!args["refresh"]) do
          finished(item, job)
        end

      # the operator deleted it while the job was queued
      {:error, :not_found} ->
        :ok
    end
  end

  # **A match that reached three of four databases has not finished.** The job
  # itself succeeded (records were written, a draft was staged), so reporting
  # success would mean never going back, and a provider rate-limited during a
  # cold start would cost that item its records until somebody noticed the
  # chip and retried by hand.
  #
  # Failing the job here is what puts it back on the queue. The partial result
  # is already stored and stays stored, so each attempt keeps whatever it got
  # and re-asks only what it missed — a provider error is never cached, while
  # the successful answers are, which is what makes a retry cheap.
  defp finished(item, %Oban.Job{attempt: attempt, max_attempts: max}) do
    case Inbox.unreached_providers(item) do
      [] ->
        :ok

      unreached when attempt < max ->
        {:error, {:providers_unreached, unreached}}

      unreached ->
        # Out of attempts. Keep what we have rather than discarding the job:
        # the outcome is already on the item, so the form shows a "couldn't be
        # reached — retry" chip, which is a better signal than a job the
        # pruner deletes tomorrow.
        Logger.warning(fn ->
          "Auto-match: gave up reaching #{Enum.join(unreached, ", ")} for item #{item.id}"
        end)

        :ok
    end
  end

  # Shared instances rate-limit with a ~30s Retry-After, so the first retry
  # waits past that rather than immediately spending another request on being
  # told no. Capped, because the point is to keep trying until the provider
  # comes back, not to schedule the last attempt for tomorrow — a cold start
  # is hundreds of items and the queue has to stay responsive.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}),
    do: trunc(min(:math.pow(2, attempt) * 30, @max_backoff))
end
